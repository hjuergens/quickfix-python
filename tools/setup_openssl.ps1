# Builds a static OpenSSL for Windows wheel builds, pinned to the same version and
# SHA256 as tools/setup_openssl.sh uses for Linux and macOS.
#
# Without this, Windows wheels take whatever OpenSSL the runner image ships and
# delvewheel vendors the DLLs. That is worse than it sounds: 1.16.0.1rc1 went out
# with OpenSSL 3.6.4 on Windows and 3.5.8 everywhere else, and 3.6 is not an LTS
# release -- its support ends 2026-11-01, where 3.5 runs to 2030-04-08. The image
# also moves without notice, so rebuilding a tag could produce a different wheel.
#
# Static, like the other platforms: nothing for delvewheel to vendor, and no DLL
# for the loader to fail to find next to the .pyd.

$ErrorActionPreference = "Stop"

$Version = "3.5.8"
$Sha256  = "a8f84a39918ec6415ce765d9b429d313ba97b8143169c172e734b9514464f5b2"
$Prefix  = if ($env:OPENSSL_ROOT_DIR) { $env:OPENSSL_ROOT_DIR } else { "C:\openssl-static" }
$Prefix  = $Prefix -replace '/', '\'

if ((Test-Path "$Prefix\lib\libssl.lib") -or (Test-Path "$Prefix\lib\libssl_static.lib")) {
    Write-Host "OpenSSL $Version already built at $Prefix, skipping"
    exit 0
}

$work = Join-Path $env:TEMP "openssl-build"
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory -Force -Path $work | Out-Null
Set-Location $work

Write-Host "== powershell $($PSVersionTable.PSVersion)"
Write-Host "== downloading OpenSSL $Version"
$url = "https://github.com/openssl/openssl/releases/download/openssl-$Version/openssl-$Version.tar.gz"
(New-Object System.Net.WebClient).DownloadFile($url, (Join-Path $PWD "openssl.tar.gz"))

# .NET rather than Get-FileHash: that cmdlet was not found in the PowerShell
# cibuildwheel runs this under, even though Invoke-WebRequest was. Do not assume
# any cmdlet beyond the language itself is present here.
$stream = [System.IO.File]::OpenRead((Join-Path $PWD "openssl.tar.gz"))
try {
    $bytes  = [System.Security.Cryptography.SHA256]::Create().ComputeHash($stream)
} finally {
    $stream.Close()
}
$actual = ([System.BitConverter]::ToString($bytes)).Replace("-", "").ToLower()
if ($actual -ne $Sha256) {
    throw "sha256 mismatch: expected $Sha256, got $actual"
}
Write-Host "== sha256 ok"

# tar ships with Windows 10+ (bsdtar).
tar -xzf "openssl.tar.gz"
Set-Location "openssl-$Version"

# Import the MSVC environment. nmake and cl are not on PATH until vcvars runs,
# and a PowerShell child process cannot inherit it any other way: run vcvars in
# cmd, dump the environment, and copy it into this session.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw "vswhere not found at $vswhere" }
$vsPath = & $vswhere -latest -products * -property installationPath
if (-not $vsPath) { throw "no Visual Studio installation found" }

switch ($env:PROCESSOR_ARCHITECTURE) {
    "ARM64" { $vcvars = "vcvarsarm64.bat"; $target = "VC-WIN64-ARM" }
    default { $vcvars = "vcvars64.bat";    $target = "VC-WIN64A" }
}
$vcvarsPath = Join-Path $vsPath "VC\Auxiliary\Build\$vcvars"
if (-not (Test-Path $vcvarsPath)) { throw "$vcvars not found at $vcvarsPath" }

Write-Host "== importing MSVC environment from $vcvars"
cmd /c "`"$vcvarsPath`" && set" | ForEach-Object {
    if ($_ -match "^([^=]+)=(.*)$") { Set-Item -Path "env:$($matches[1])" -Value $matches[2] }
}

# NASM is optional: without it OpenSSL needs no-asm, which builds fine but gives
# up the assembly crypto paths. Prefer the assembly build when the tool is there.
$asmArgs = @()
$nasm = cmd /c "where nasm 2>nul"
if (-not $nasm) {
    Write-Host "== nasm not found, configuring no-asm"
    $asmArgs = @("no-asm")
}

Write-Host "== configuring $target (static) -> $Prefix"
& perl Configure $target no-shared no-tests @asmArgs "--prefix=$Prefix" "--openssldir=$Prefix"
if ($LASTEXITCODE -ne 0) { throw "Configure failed" }

& nmake
if ($LASTEXITCODE -ne 0) { throw "nmake failed" }

& nmake install_sw
if ($LASTEXITCODE -ne 0) { throw "nmake install_sw failed" }

Write-Host "== done: $Prefix"
cmd /c "dir /b `"$Prefix\lib\*.lib`"" | ForEach-Object { Write-Host "   $_" }
