# Building QuickFIX from source

Environment prerequisites and the gotchas that cost real debugging time. For the plain
build commands see the [README](README.md); for wheel packaging and SWIG regeneration see
[AGENTS.md](AGENTS.md).

## Windows

### Smart App Control must be off

**This is the first thing to check on a fresh Windows 11 machine.** Smart App Control
(SAC) blocks every unsigned binary that lacks a cloud reputation — which is exactly what
a local build produces. `ut.exe`, `at.exe`, `pt.exe` and the `_quickfix` extension all
fail to launch, from any shell:

```
Eine Anwendungssteuerungsrichtlinie hat diese Datei blockiert
(An application control policy has blocked this file)
```

SAC has **no exclusion list** — no per-file, per-folder or per-publisher exception
exists. Its only states are Off, Evaluation and Enforcement, so the feature is
fundamentally incompatible with local native development.

Check the current state:

```powershell
(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy').VerifiedAndReputablePolicyState
# 0 = Off, 1 = Enforcement, 2 = Evaluation
```

Confirm what it blocked (event ID 3077 = enforcement block, 3076 = evaluation):

```powershell
Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 100 |
  Where-Object Id -in 3076,3077
```

Turn it off via Settings → Privacy & Security → Windows Security → App & browser
control → Smart App Control settings → **Off**, or from an elevated shell:

```powershell
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' `
  -Name VerifiedAndReputablePolicyState -Value 0 -Type DWord -Force
citool.exe -r
```

> **Turning SAC off is a one-way operation.** Re-enabling it requires a clean install or
> a PC reset — SAC can only be switched on during a clean install. Microsoft intends SAC
> to disable itself automatically for users it detects as developers; if it hasn't, this
> is the documented way to do it. On a company-managed machine, check with IT first.

### Toolchain

- **Visual Studio 2022** with the C++ workload (MSVC, C++17).
- **CMake 3.13+** — the `cmake -B <dir>` form used throughout the docs needs 3.13.
- **OpenSSL**, for `-DHAVE_SSL=ON`. vcpkg is the reproducible source:

  ```powershell
  vcpkg install openssl:x64-windows
  # -> <vcpkg>\installed\x64-windows
  ```

- **Python 3**, for `-DHAVE_PYTHON3=ON`. This project *is* the Python binding, so build
  with Python enabled unless you are deliberately testing the C++-only path.
- **Ruby**, *only* to run the acceptance suite — `runat.bat` / `runat.sh` drive the FIX
  session tests through `Runner.rb`. Not needed to build, and not needed for the unit or
  performance suites. `winget install RubyInstallerTeam.Ruby` on Windows.

### Configure and build

```powershell
cmake -S . -B build -DHAVE_SSL=ON -DHAVE_PYTHON3=ON `
  -DOPENSSL_ROOT_DIR="C:\path\to\vcpkg\installed\x64-windows"
cmake --build build --config Release
```

A correct configure reports Python with the **Interpreter** component present:

```
-- Found Python3: ... found components: Interpreter Development Development.Module Development.Embed
```

`Interpreter` is required, not optional. Without it `FindPython3` cannot run the
interpreter to determine its ABI, so a free-threaded build looks for `python3XX.lib`
instead of `python3XXt.lib` and reports `Development` as missing.

### The OpenSSL DLLs must be on PATH to *run*

The `x64-windows` vcpkg triplet is a **shared** build, so the test binaries link against
`libssl-3-x64.dll` / `libcrypto-3-x64.dll`. They build fine but fail at launch with
`0xC0000135 STATUS_DLL_NOT_FOUND` — which looks like a broken build, but isn't:

```powershell
$env:PATH = "C:\path\to\vcpkg\installed\x64-windows\bin;$env:PATH"
```

Use the `x64-windows-static-md` triplet to avoid this, at the cost of a larger binary.
For wheels, vendor the DLLs with `delvewheel` instead — see [AGENTS.md](AGENTS.md).

## Running the tests

Binaries land in `test\<config>\<name>\` on Windows and `lib/` on Linux. Each suite needs
its config and spec paths, and the acceptance suite needs a free TCP port.

The SSL-enabled build links against the shared OpenSSL DLLs, so put the vcpkg `bin`
directory on `PATH` first (see above) or every binary dies with `0xC0000135`.

```powershell
cd test
..\test\release\ut\ut.exe --quickfix-config-file cfg/ut.cfg --quickfix-spec-path ../spec
.\runat.bat release 6666          # acceptance; needs Ruby and ports 6666-6670
..\test\release\pt\pt.exe --quickfix-spec-path ../spec -# "~[network]"
```

```bash
# Linux / macOS
cd test
./ut --quickfix-config-file cfg/ut.cfg --quickfix-spec-path ../spec
./runat.sh 6666
./pt --quickfix-spec-path ../spec -# "~[network]"
```

### Known failure on non-English Windows

One unit test fails on a localized Windows install:

```
CHECK( expected == FIX::error_wsaerror(10048L) )
  "(wsaerror[10048]:Only one usage of each socket address ...)"
  == "(wsaerror[10048]:Normalerweise darf jede Socketadresse ...)"
```

[`UtilityTestCase.cpp`](src/C++/test/UtilityTestCase.cpp) hardcodes the English Winsock
message, while `FormatMessage` returns text in the system language. This is a test bug,
not a build or library problem — expect 53/54 rather than 54/54 on a German system.

## Line endings when exporting the tree

If `core.autocrlf=true` (the Windows default), **`git archive` writes CRLF into the
tarball** even though the repository blobs are LF. Unpacked on Linux, every shell script
dies with exit 127 (`required file not found`) because the `#!/bin/sh\r` shebang is not a
valid interpreter path, and the `.def`/`.cfg` files the Ruby acceptance runner compares
literally are corrupted too. Compiled C++ is unaffected, so the build succeeds while
every script-driven test fails.

```bash
git -c core.autocrlf=false archive --format=tar HEAD -o src.tar
```

CI never hits this, since Linux runners check out LF directly.
