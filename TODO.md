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

## Python examples

`examples/` ships three C++ demo programs and almost no Python. `examples/executor/python/executor.py`
is 86 lines, unreferenced by any build file, and its `toAdmin`/`fromAdmin`/`toApp` take
`(self, sessionID, message)` - the wrong order, harmless only because the bodies are empty.
`tradeclient` and `ordermatch` have no Python at all. Since the project publishes a wheel
(`quickfix-tls`), Python users are a first-class audience with no runnable example.

The obstacle is `FIX::MessageCracker`: every C++ example inherits from it and overrides typed
`onMessage(const FIX42::NewOrderSingle&, ...)` overloads, but it is not wrapped and cannot
practically be - it dispatches to ~640 typed C++ message classes that SWIG never sees
(`grep -c "FIX42::" src/python/QuickfixPython.cpp` returns 0), and `quickfix42.NewOrderSingle`
is hand-written Python over `fix.Message`. A pure-Python cracker gives the same ergonomics with
no SWIG regeneration.

A worked design for porting `executor` and `tradeclient` - the cracker module, the two ports, a
unit test, an end-to-end CI smoke test, and the gotchas that will bite (`Py_Exit(1)` on any
callback exception, the non-blocking `start()`, teardown segfaults, shared `FileStorePath`) - is
in [.claude/plans/python-examples-port.md](.claude/plans/python-examples-port.md). `ordermatch`
is deliberately excluded there: its matching engine is ~440 lines of C++ business logic with no
binding behind it, so it would be a rewrite rather than a port.
