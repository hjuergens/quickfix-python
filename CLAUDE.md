# QuickFIX Python Bindings — Build Notes

This repo is the QuickFIX C++ engine with Python bindings generated via SWIG.

There are two ways to build the Python module, and they share one CMake source list:

- **In-tree** (this file): a CMake/Autotools target, for developing against the
  bindings from the source tree.
- **As a wheel**: `pyproject.toml` drives the same CMake build through
  scikit-build-core and publishes as `quickfix-tls`. See the
  **Building a Python wheel** section of [AGENTS.md](AGENTS.md) — do not duplicate
  the wheel instructions here.

There is no `setup.py`. See [AGENTS.md](AGENTS.md) for general C++ build/test/style
conventions; this file covers the in-tree Python build.

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

- Built shared library: `lib/_quickfix.so` (`.pyd` on Windows — suffix handled
  explicitly in `src/python3/CMakeLists.txt`). `lib/python3/` is the `cmake --install`
  destination, not the build output, and does not exist until you install; to import
  straight from the tree use `PYTHONPATH=lib:src/python3`.
- Generated Python wrapper sources live directly under `src/python3/`
  (`quickfix.py`, `quickfix_fields.py`, `quickfix40-50sp2.py`, `quickfixt11.py`,
  `QuickfixPython.cpp/.h`). These are committed as **regular files**, not
  symlinks — a past bug (fixed in `8a7a416e`) stored them as symlinks pointing at
  `../python/...`, which broke checkout on Linux/macOS ("Filename too long",
  since a symlink's git blob is its target path). Don't reintroduce symlinks here.
  Note `src/python3/QuickfixPython.cpp` and `.h` are one-line `#include` shims for
  `../python/QuickfixPython.cpp` — regular files, but the generated content itself
  lives under `src/python/`. The `.py` wrappers are full copies.

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
  properly link `Python3::Module`/`Python3::Python`.
- Wheel CI now exists: `.github/workflows/wheels.yml` runs cibuildwheel across six
  **native** runners (manylinux x86_64/aarch64, win_amd64/arm64, macOS x86_64/arm64)
  plus a free-threaded lane. Still no emulation and no cross-compilation, so the
  "build natively" rule above continues to hold.
- `1807eb00` fixed the Windows build: added `.pyd` suffix and corrected the
  python3 install directory.
