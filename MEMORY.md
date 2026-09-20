# Project memory

Decisions this fork has made and the reasoning behind them, so they are not relitigated or
silently reversed. Open work lives in [TODO.md](TODO.md) and conventions and how-to in [AGENTS.md](AGENTS.md).
Designs that are approved but unbuilt belong in `.claude/plans/` — note that directory does
not exist on `master` yet: the first such plan (porting the `executor` and `tradeclient`
examples to Python) is sitting on the unmerged branch `docs/python-examples-plan`.

Each entry says what was decided, why, and what it costs — the cost matters, because a
decision recorded without its downside looks like a free choice to whoever reads it next.

## What this fork is for

Upstream `quickfix/quickfix` publishes an **sdist only**, built without SSL, through
`quickfix/quickfix-package` (shell scripts that copy sources out of the engine tree and run
`setup.py sdist`). This fork exists to publish **binary wheels with TLS** as `quickfix-tls`,
which is why `ThreadedSSLSocketInitiator`/`Acceptor` are exposed to Python here and why the
wheel machinery is elaborate. Nothing about the wheel path is shared with upstream, so every
problem found in it is novel and unshared.

**Nothing has been published yet** — neither PyPI nor TestPyPI has ever received a release,
and no publish job has ever executed. The OIDC trusted-publishing path is therefore unproven.

## CMake is the only build system (2026-09-17)

Autotools was deleted, along with the Ruby bindings it was the only builder for.

**Why:** it had stopped building what it claimed. `AC_CONFIG_HEADERS` generated
`src/C++/config_unix.h`, which *nothing in the tree ever included* — every source includes
`src/C++/config.h`, a tracked CMake artifact whose committed content is `/* #undef HAVE_SSL */`.
Since the SSL sources are wrapped in `#if (HAVE_SSL > 0)`, `./configure --with-openssl`
compiled them to empty translation units, and every other `AC_DEFINE` reached no compiler.
Two build systems had also diverged on the C++ standard (C++11 vs C++17) and on what gets
installed.

**Cost:** `make dist`, `make uninstall`, the `make generate` alias and `--with-allocator` are
gone; the first three have no CMake equivalent. Recorded in TODO.md.

## Every test suite is registered with CTest (2026-09-17)

Before this, `TESTS` in two `Makefile.am` files was the only thing that ran any test, and the
CMake lane invoked binaries by hand in YAML — including a step that *skipped* a suite when its
binary was missing, so a build regression reported green.

Turning the Python tests on for the first time immediately found three shipping bugs: macOS
built `_quickfix.dylib` where Python only imports `.so`; Windows could not resolve OpenSSL's
DLLs; and Windows aborted loading a certificate, because `UtilitySSL.cpp` passed a `FILE*`
across a CRT boundary (fixed by reading through `BIO_new_file`). None had ever been caught,
because the only check was "it compiled".

**Cost:** `cpp.acceptance` runs on Linux only — see TODO.md for what the other two platforms
do instead and why.

## The generated SWIG wrapper is checked for drift in CI (2026-09-19)

`src/python/QuickfixPython.cpp` is committed, ~6 MB, and no build regenerates it, so an edit
to a `.i` file silently does nothing until someone runs the recipe by hand. The
`SWIG bindings` workflow now regenerates with a pinned SWIG 4.2.1 and fails if the result
differs, uploading the regenerated bindings as an artifact.

It found a dead `SWIGRUBY` block on its first run — 143 lines the Ruby removal should have
taken out days earlier. `tools/setup_openssl.sh`'s sibling, `tools/regenerate_swig.sh`, is the
whole recipe including the two steps AGENTS.md says regeneration silently discards.

**Cost:** the job builds SWIG from source (cached), because distro packages drift and a
different version rewrites all 6 MB.

## Wheels pin their own OpenSSL (2026-09-19)

Linux wheels were baking in the manylinux container's OpenSSL **1.1.1k**, end of life since
September 2023. They now build a pinned static 3.5.8, as macOS already did.

The reasoning that matters is in AGENTS.md under *What a wheel freezes*: a wheel pins whatever
it was built against, vendored or static, so "the user's distro patches it" was never true.

**Cost:** this repo owns OpenSSL CVE response for its wheels, and the manylinux container now
needs `perl-core` to build it.

## Interpreter coverage is explicit, not automatic (2026-09-20)

The wheel matrix listed no interpreters, so a new CPython arrived automatically. CPython 3.15
then turned out to abort at interpreter finalization, and because the publish job needs every
build job, one broken interpreter blocked every platform at once.

**Cost:** someone has to remember to add a version once it is released and tested.

## Ruby is still required — for the tests

The Ruby *bindings* were deleted; `test/*.rb` was not. The acceptance suite is
`ruby -I. Runner.rb` driving 468 `.def` scripts, and `spec/Generator*.rb` generates the C++ and
Python message classes. Do not "finish removing Ruby".
