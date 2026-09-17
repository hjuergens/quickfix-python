# TODO

## Wheel coverage gaps

Unlike the free-threaded lane (`build_wheels_freethreaded` in
[.github/workflows/wheels.yml](.github/workflows/wheels.yml)), which is red for two
concrete, tracked upstream reasons, these two are simply not built yet, with no
recorded blocker:

- **musllinux wheels** (Alpine and other musl-based distros). Currently skipped via
  `skip = [..., "*-musllinux_*", ...]` in `pyproject.toml`'s `[tool.cibuildwheel]`.
  Falls back to the source archive today, which works but requires a C++17 compiler
  and OpenSSL dev headers in the container.
- **PyPy wheels**. Currently skipped via `skip = [..., "pp*", ...]` in the same
  section, and not mentioned at all in `README-PyPI.md`'s supported-platforms table.
  SWIG-generated extensions tend to need extra work under PyPy's `cpyext` layer, so
  this needs investigation before it can be added to the `cibuildwheel` matrix.

Neither is an SSL gap - `HAVE_SSL=ON` is set once, globally, in
`[tool.scikit-build.cmake.define]`, so any platform that gets a wheel (or installs
from source) already builds with SSL enabled by default.

## CI correctness gaps

Both found while tracing the red master builds of 2026-09-12/13, both left alone in
`8b3beb06` because neither is what was breaking the build:

- **CMake builds against the wrong Python.** `build_test_cmake.yml` pins
  `actions/setup-python` to 3.12 (and the action exports `Python3_ROOT_DIR`), but
  `find_package(Python3 ...)` defaults to `Python3_FIND_STRATEGY=VERSION`, which
  takes the highest version it can find rather than the hinted one. The Windows
  Debug log shows `Found Python3: .../Python/3.14.7/x64/python3.exe`. So the matrix
  does not test the version it claims to, and the pin is silently inert. Fix by
  setting `Python3_FIND_STRATEGY=LOCATION` or requiring an explicit version.
- ~~**`src/python3/test.sh` hides failing tests.**~~ Resolved: the seven Python test
  cases are registered with CTest individually, so each one's status is reported on
  its own and `test.sh` is gone.


## Dropped with Autotools

Removed along with `configure.ac` and the `Makefile.am` tree, with no CMake replacement.
None is believed to be in use; recorded here so the loss is deliberate rather than
discovered:

- **`make dist`** - the `EXTRA_DIST` lists. In practice scikit-build-core already builds
  the sdist (`pyproject.toml`), and there is no CPack configuration.
- **`make uninstall`** - `uninstall-local` in `src/C++/Makefile.am`. CMake has no
  uninstall target either; this was already a gap on that side.
- **`make generate`** - an alias for `cd spec && bash generate.sh`. The script itself is
  untouched; only the `make` entry point is gone.
- **`--with-allocator`** (`m4/ax_allocator.m4`) - it selected between the
  `ENABLE_*_ALLOCATOR` branches in `src/C++/Utility.h`. Already inert: it wrote
  `src/C++/config_unix.h`, which nothing in the tree ever included, so those branches
  have been unreachable regardless of how configure was invoked.

Still stale, and unrelated to CMake: `test/runat_python3.sh`, `test/runut_python3.sh` and
`src/python/test-python3.sh` all export `LD_LIBRARY_PATH=.../.libs` and
`PYTHONPATH=../../lib/python3`, paths only libtool and the Autotools `all-local` symlink
rules ever produced. They need porting to the CMake layout (`lib/` and `src/python3/`)
or deleting.
