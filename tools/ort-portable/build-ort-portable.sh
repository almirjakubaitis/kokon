#!/usr/bin/env bash
# Builds a portable ONNX Runtime for Kokon: baseline x86-64-v2 (SSE4.2 + POPCNT), with the
# AVX/AVX2/AVX-512 kernels still compiled and chosen at runtime by MLAS.
#
#   bash tools/ort-portable/build-ort-portable.sh
#
# Result: $KOKON_DEPS/ort-portable/lib/libonnxruntime.a (Linux) or onnxruntime.lib (Windows,
# see build-ort-portable.ps1). Point ORT_LIB_LOCATION at that lib folder when building Kokon:
#
#   export ORT_LIB_LOCATION=$HOME/kokon-deps/ort-portable/lib
#   cargo build -p qls-service --release
#
# Why not ort's prebuilt binaries: they are built with -march=x86-64-v3 / AVX2 baseline and
# stop with SIGILL on a Xeon X5670 (SSE4.2, no AVX). See README.md.
set -euo pipefail

ORT_VERSION="${ORT_VERSION:-v1.31.0}"
KOKON_DEPS="${KOKON_DEPS:-$HOME/kokon-deps}"
SRC="$KOKON_DEPS/onnxruntime"
BUILD="$KOKON_DEPS/ort-build"
PREFIX="$KOKON_DEPS/ort-portable"
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ "${1:-}" = "--clean" ]; then
  rm -rf "$BUILD" "$PREFIX"
fi

if [ ! -d "$SRC/.git" ]; then
  echo "==> Cloning ONNX Runtime $ORT_VERSION into $SRC"
  mkdir -p "$KOKON_DEPS"
  git clone --recursive --depth 1 --branch "$ORT_VERSION" https://github.com/microsoft/onnxruntime "$SRC"
fi

# The app and ORT must agree on the C++ toolchain: Ubuntu 22.04's g++ 11 is too old for the
# libstdc++ ORT is built with, and the release build uses g++-13 (docs/linux.md).
if command -v gcc-13 >/dev/null && command -v g++-13 >/dev/null; then
  export CC="${CC:-gcc-13}"
  export CXX="${CXX:-g++-13}"
fi

GEN=()
if command -v ninja >/dev/null; then
  GEN=(-G Ninja)
fi

# x86-64-v2 is SSE4.2 + POPCNT, the floor we support. The USE_AVX* options control the
# baseline of the rest of ORT; the MLAS AVX/AVX2/AVX-512 kernels keep their own per-file
# flags and are selected at runtime, so newer CPUs still get them.
MARCH=()
case "$(uname -m)" in
  x86_64|amd64) MARCH=(-DCMAKE_C_FLAGS="-march=x86-64-v2" -DCMAKE_CXX_FLAGS="-march=x86-64-v2") ;;
esac

echo "==> Configuring ONNX Runtime (portable, CPU only)"
cmake -S "$HERE" -B "$BUILD" "${GEN[@]}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DONNXRUNTIME_SOURCE_DIR="$SRC" \
  "${MARCH[@]}" \
  -Donnxruntime_USE_AVX=OFF \
  -Donnxruntime_USE_AVX2=OFF \
  -Donnxruntime_USE_AVX512=OFF \
  -Donnxruntime_BUILD_UNIT_TESTS=OFF \
  -Donnxruntime_CLIENT_PACKAGE_BUILD=ON \
  -Donnxruntime_USE_KLEIDIAI=OFF \
  --compile-no-warning-as-error

echo "==> Building (this takes a while)"
cmake --build "$BUILD" --config Release --parallel "$(nproc)"

echo "==> Installing to $PREFIX"
cmake --install "$BUILD" --config Release

LIB="$PREFIX/lib/libonnxruntime.a"
[ -f "$LIB" ] || { echo "✗ $LIB was not produced"; exit 1; }
echo "✓ Portable ONNX Runtime: $LIB ($(du -h "$LIB" | cut -f1))"
echo "  Use: export ORT_LIB_LOCATION=$PREFIX/lib"
