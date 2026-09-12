# QuickFIX Python Bindings — Build Notes

This repo is the QuickFIX C++ engine with Python bindings generated via SWIG.
There is no `setup.py`/`pyproject.toml` — the Python module is built as a
CMake/Autotools target, not a standalone pip package. See [AGENTS.md](AGENTS.md)
for general C++ build/test/style conventions; this file covers the Python-specific
build.

## Native build (preferred — no cross-compiling)

Always build natively on the target OS/arch. CI itself never cross-compiles: the
`build_test_cmake.yml` matrix runs windows-2022/ubuntu-latest/macos-latest each as
their own native runner. Follow the same pattern locally — build on Linux for
Linux, on macOS for macOS, on Windows for Windows.

```bash
# Configure with Python 3 bindings enabled
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DHAVE_PYTHON3=ON

# Optionally also -DHAVE_SSL=ON if SSL support is needed

# Build
cmake --build build
```

Requirements:
- C++17 compiler
- CMake ≥ 3.12 (uses `find_package(Python3 REQUIRED COMPONENTS Development)`;
  falls back to `find_package(PythonLibs 3 REQUIRED)` on older CMake)
- SWIG (bindings are checked in pre-generated at SWIG 4.2.1; only needed if
  regenerating from the `.i` interface files)

Legacy Autotools path (still exercised by `build_test_autotools.yml`):

```bash
./bootstrap && ./configure && make && make check
```

## Output locations

- Built shared library: `lib/python3/_quickfix` (`.so` on Linux/macOS, `.pyd` on
  Windows — Windows suffix handled explicitly in `src/python3/CMakeLists.txt`).
- Generated Python wrapper sources live directly under `src/python3/`
  (`quickfix.py`, `quickfix_fields.py`, `quickfix40-50sp2.py`, `quickfixt11.py`,
  `QuickfixPython.cpp/.h`). These are committed as **regular files**, not
  symlinks — a past bug (fixed in `8a7a416e`) stored them as symlinks pointing at
  `../python/...`, which broke checkout on Linux/macOS ("Filename too long",
  since a symlink's git blob is its target path). Don't reintroduce symlinks here.

## Regenerating SWIG bindings

Only needed when editing `src/python/quickfix.i`:

```bash
cd src/python
./swig.sh
```

This regenerates `QuickfixPython.cpp` and the `.py` wrapper modules, which are
then copied/used by both `src/python/` (py2 legacy) and `src/python3/` build trees.

## Notes from recent history

- `39e7a84a` widened the CMake Python3 discovery to support newer CMake and
  properly link `Python3::Module`/`Python3::Python`; still native per-runner,
  no cross-arch/manylinux/cibuildwheel setup exists in this repo.
- `1807eb00` fixed the Windows build: added `.pyd` suffix and corrected the
  python3 install directory.
