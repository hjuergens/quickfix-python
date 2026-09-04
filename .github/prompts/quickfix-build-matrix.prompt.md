---
name: "QuickFIX Build Matrix"
description: "Build and validate QuickFIX across Windows and Linux versions, distributions, architectures, Python versions, and SSL configurations."
argument-hint: "Specify operating systems, Linux distributions and versions, build tools, architectures, Python versions, OpenSSL location, and whether to edit CI or only run builds."
agent: "agent"
---

Build and validate this QuickFIX checkout across the requested Windows/Linux, build-tool, architecture, Python, and OpenSSL matrix.

## Inputs

Use the user's request and any supplied arguments for:

- Windows versions or runner images
- Linux distributions and versions or runner images, such as Ubuntu, Debian, Fedora, or Rocky Linux
- Build tools and versions, such as Visual Studio generators, Ninja, Make, GCC, Clang, or CMake
- Target architectures, defaulting to the native architecture plus any explicitly requested cross-compilation architectures
- Python versions, defaulting to the versions explicitly supported by the current environment
- OpenSSL version and installation root
- Dependency provider: system packages, vcpkg classic mode, or a pinned vcpkg manifest/triplet
- vcpkg root, version or commit, triplet, registry baseline, binary cache, and asset cache when vcpkg is requested
- Wheel mode: build wheels, verify existing wheels, or build and publish locally; target Python ABI tags, platforms, architectures, and artifact directory
- Build configuration, defaulting to `Release`
- Whether to update CI, add scripts, or only execute and report the matrix

When an input is omitted, inspect the repository, CI definitions, and installed tools before choosing a default. State every default before running commands. Do not claim a version, distribution, architecture, interpreter, compiler, generator, or OpenSSL installation was validated unless it was actually selected and used.

## Repository context

Read the applicable project guidance and existing build definitions first:

- [AGENTS.md](../../AGENTS.md)
- [CMakeLists.txt](../../CMakeLists.txt)
- [README.md](../../README.md)
- [README.SSL](../../README.SSL)
- [CMake workflow](../workflows/build_test_cmake.yml), if present
- [Autotools workflow](../workflows/build_test_autotools.yml), if present
- [Python binding build](../../src/python3/CMakeLists.txt)
- [Python binding source](../../src/python/quickfix.i)
- [Windows unit-test runner](../../test/runut.bat)
- [Windows acceptance-test runner](../../test/runat.bat)
- Linux test and Python runners under [test](../../test/) and [src/python3](../../src/python3/)

Prefer the repository's existing CMake options, target names, test runners, naming, and output paths. Preserve unrelated working-tree changes.

## Required workflow

1. Inspect available CMake, generators, compilers, Python interpreters/development packages, OpenSSL installations, and vcpkg installations on each platform. Verify that each requested matrix entry is available before configuring it. For Linux, identify the distribution, release, package manager, libc, kernel architecture, compiler version, and installed development packages.
2. Resolve compatibility constraints from the repository, especially the minimum CMake version, C++ standard, Python binding discovery, Visual Studio multi-config behavior, Linux single-config behavior, architecture or cross-compilation requirements, libc differences, and SSL linking requirements. Confirm whether the checkout contains Python 2 support before using any `HAVE_PYTHON` claim; this checkout's current CMake path uses `HAVE_PYTHON3` and `PythonLibs 3`.
3. Create an isolated build directory for every matrix combination. Never reuse a cache across different operating systems, distributions, releases, generators, compilers, architectures, Python versions, OpenSSL versions, vcpkg triplets, or dependency providers.
4. If vcpkg is selected, prefer manifest mode with a committed baseline and lock the vcpkg repository to a known release or commit. Install dependencies for the exact triplet, pass `-DCMAKE_TOOLCHAIN_FILE=<vcpkg-root>/scripts/buildsystems/vcpkg.cmake`, and pass `-DVCPKG_TARGET_TRIPLET=<triplet>`. Record the manifest, baseline, triplet, overlays, binary-cache settings, and whether packages were restored from cache. Use vcpkg for OpenSSL and other supported native dependencies, but do not assume it supplies the QuickFIX Python bindings or Python development files.
5. Configure with the smallest appropriate option set. For this checkout's Python bindings use `-DHAVE_PYTHON3=ON` and bind the selected Python interpreter/development files using the project-supported CMake variables. For a legacy checkout, test `-DHAVE_PYTHON=ON` only after verifying its CMake and source support. For SSL use `-DHAVE_SSL=ON`; when vcpkg supplies OpenSSL, let the toolchain's package configuration resolve it, otherwise set `-DOPENSSL_ROOT_DIR=...` when required. Pass the appropriate architecture/toolchain options for cross-compilation. Keep tests enabled unless the user requests otherwise.
6. Build the selected configuration with the correct multi-config or single-config command. Capture the exact configure and build commands, including the shell, environment variables, generator, toolset, architecture, package paths, vcpkg triplet, and Python executable.
7. Run focused validation for each successful build: the QuickFIX unit tests, Python binding import/build tests when Python is enabled, and SSL-related coverage or examples when SSL is enabled. Verify that the built Python extension is importable by the selected interpreter and that its runtime dependency paths are correct. Run acceptance tests only when their required configuration and ports are available; do not consume ports 6666-6670 without checking availability first.
8. If a combination fails, classify it as an environment/setup failure, repository/configuration failure, compile/link failure, Python ABI/import failure, vcpkg/package-resolution failure, test failure, or unsupported combination. Keep going with independent combinations unless the environment makes all remaining entries impossible.
9. If the user requested CI or script changes, make the smallest change consistent with the existing workflows. Define Linux package-install steps for every distro family, document architecture-specific prerequisites, and make vcpkg setup reproducible with a pinned baseline and cache configuration. Do not add a matrix entry that cannot be reproduced locally or whose dependencies are undocumented.
10. After edits, run the narrowest relevant validation first, then the affected build/test command. Do not commit changes.
11. When wheel mode is requested, build one isolated wheel per Python ABI and platform/architecture combination. Prefer the repository's supported Python packaging path; if none exists, inspect the SWIG/CMake packaging layout before choosing a minimal `pyproject.toml` or wheel-building integration. Do not silently copy binaries between Python ABIs.
12. For each wheel, verify the filename tags, inspect its contents, install it into a clean virtual environment for the matching Python version, import `quickfix`, exercise a small binding operation, and run the relevant Python tests. On Linux, check shared-library dependencies and use the project's supported manylinux or equivalent policy when publishing portable wheels. On Windows, verify the correct MSVC runtime and architecture. On macOS, verify the deployment target and architecture if macOS is included.
13. If a wheel cannot be built or is not portable, report the exact missing packaging support or platform constraint. Keep source builds and wheel builds separate, and never describe a source package or locally installable wheel as a publishable cross-platform artifact without the corresponding audit/compatibility checks.

## Output format

Return a compact report with these sections:

### Matrix

A table with one row per requested combination and columns for OS/runner, Linux distribution and release when applicable, generator/toolset, compiler, architecture, Python/ABI tag, OpenSSL, dependency provider, vcpkg triplet when applicable, wheel tag/artifact, build directory, and status.

### Commands

List the exact configure, build, dependency-install, vcpkg bootstrap/install, wheel-build, wheel-audit, install, and test commands used for each successful or failed combination. Use fenced `powershell` blocks for Windows commands and fenced `bash` blocks for Linux commands.

### Results

Summarize passed tests and failures. For every failure include the first actionable error, the affected matrix row, and whether the cause is reproducible, environmental, or unsupported.

### Changes

List files changed, or state `No files changed` when this was an execution-only validation.

### Follow-up

List only concrete remaining gaps, such as unavailable Windows or Linux images, missing Python development packages, absent OpenSSL artifacts, unavailable architectures or cross toolchains, distro-specific package gaps, unpinned vcpkg state, unavailable vcpkg triplets or binary caches, missing wheel tooling, unsupported Python ABI tags, failed wheel audits, or combinations that require CI rather than the current machine.

Do not invent test results, installed versions, paths, distro support, architecture support, or compatibility guarantees. If the full matrix cannot run on the current host, produce a reproducible CI matrix and clearly label the entries that still require CI validation.
