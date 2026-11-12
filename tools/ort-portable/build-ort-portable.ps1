# Builds a portable ONNX Runtime for Kokon on Windows: MSVC's x64 baseline (SSE2; it runs on
# every machine Kokon supports), with MLAS's AVX/AVX2/AVX-512 kernels still compiled and chosen
# at runtime. Do NOT add /arch:AVX or /arch:AVX2 here: that is what makes ort's prebuilt
# libraries crash on a Xeon X5670.
#
#   powershell -ExecutionPolicy Bypass -File tools\ort-portable\build-ort-portable.ps1
#
# Result: %USERPROFILE%\kokon-deps\ort-portable\lib\onnxruntime.lib
# Then, before scripts\build-release.ps1:
#
#   $env:ORT_LIB_LOCATION = "$env:USERPROFILE\kokon-deps\ort-portable\lib"
#
# Needs: Visual Studio 2022 (Desktop C++), CMake >= 3.26, Python 3, Git.
# See README.md.
$ErrorActionPreference = 'Stop'

$OrtVersion = if ($env:ORT_VERSION) { $env:ORT_VERSION } else { 'v1.31.0' }
$Deps = if ($env:KOKON_DEPS) { $env:KOKON_DEPS } else { Join-Path $env:USERPROFILE 'kokon-deps' }
$Src = Join-Path $Deps 'onnxruntime'
$Build = Join-Path $Deps 'ort-build'
$Prefix = Join-Path $Deps 'ort-portable'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

if ($args -contains '--clean') {
    Remove-Item -Recurse -Force $Build, $Prefix -ErrorAction SilentlyContinue
}

if (-not (Test-Path (Join-Path $Src '.git'))) {
    Write-Host "==> Cloning ONNX Runtime $OrtVersion into $Src" -ForegroundColor Cyan
    New-Item -ItemType Directory -Force $Deps | Out-Null
    git clone --recursive --depth 1 --branch $OrtVersion https://github.com/microsoft/onnxruntime $Src
    if ($LASTEXITCODE) { throw "git clone failed" }
}

Write-Host "==> Configuring ONNX Runtime (portable, CPU only)" -ForegroundColor Cyan
cmake -S $Here -B $Build -G "Visual Studio 17 2022" -A x64 `
    -DCMAKE_BUILD_TYPE=Release `
    -DCMAKE_INSTALL_PREFIX="$Prefix" `
    -DONNXRUNTIME_SOURCE_DIR="$Src" `
    -Donnxruntime_USE_AVX=OFF `
    -Donnxruntime_USE_AVX2=OFF `
    -Donnxruntime_USE_AVX512=OFF `
    -Donnxruntime_BUILD_UNIT_TESTS=OFF `
    -Donnxruntime_CLIENT_PACKAGE_BUILD=ON `
    -Donnxruntime_USE_KLEIDIAI=OFF `
    -DONNX_USE_MSVC_STATIC_RUNTIME=OFF `
    -Dprotobuf_MSVC_STATIC_RUNTIME=OFF `
    -Dgtest_force_shared_crt=ON `
    -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL `
    --compile-no-warning-as-error
if ($LASTEXITCODE) { throw "CMake configure failed" }

Write-Host "==> Building (this takes a while)" -ForegroundColor Cyan
cmake --build $Build --config Release --parallel
if ($LASTEXITCODE) { throw "CMake build failed" }

Write-Host "==> Installing to $Prefix" -ForegroundColor Cyan
cmake --install $Build --config Release
if ($LASTEXITCODE) { throw "CMake install failed" }

$lib = Join-Path $Prefix 'lib\onnxruntime.lib'
if (-not (Test-Path $lib)) { throw "$lib was not produced" }
$mb = [math]::Round((Get-Item $lib).Length / 1MB, 1)
Write-Host "OK Portable ONNX Runtime: $lib ($mb MB)" -ForegroundColor Green
Write-Host "Set: `$env:ORT_LIB_LOCATION = '$Prefix\lib'" -ForegroundColor Green
