# Releasing `quickfix-tls`

Wheels are built by [`.github/workflows/wheels.yml`](.github/workflows/wheels.yml) and
published to PyPI by the `publish` job, which runs **only** on a `v*` tag.

## One-time setup

Publishing uses [PyPI trusted publishing](https://docs.pypi.org/trusted-publishers/), so
no API token is ever stored in the repository.

1. **Reserve the name.** `quickfix-tls` is unclaimed. Whoever uploads first owns it, and
   the choice is permanent - a project name cannot be renamed or reused later.

2. **Register the trusted publisher** on PyPI (Your projects -> Publishing, or, for a
   project that does not exist yet, "Add a pending publisher"):

   | Field | Value |
   |---|---|
   | PyPI project name | `quickfix-tls` |
   | Owner | `hjuergens` |
   | Repository | `quickfix-python` |
   | Workflow name | `wheels.yml` |
   | Environment name | `pypi` |

3. **Create the `pypi` GitHub environment** (Settings -> Environments -> New). The publish
   job references it, and it is the right place to add a required reviewer so a tag push
   cannot publish without a human approving it.

## Versioning

`<upstream>.<fork-revision>` - the first three segments are the upstream QuickFIX
release this is built from, the fourth counts fork releases against it.

| Situation | Version |
|---|---|
| First release built on upstream 1.16.0 | `1.16.0.1` |
| Fork-only change against the same upstream | `1.16.0.2` |
| Upstream releases 1.16.1 and we rebase | `1.16.1.1` |
| Pre-release of the above | `1.16.1.1rc1` |

This sorts correctly: `1.16.0 < 1.16.0.1 < 1.16.0.2 < 1.16.1 < 1.16.1.1`. It also lets
a consumer pin `quickfix-tls==1.16.0.*` to one upstream base while still taking fork
fixes.

Three rules that matter:

- **Never publish a bare upstream number.** Upstream's own `quickfix 1.16.0` exists on
  PyPI and differs from this build - it ships source-only, without the SSL transports.
  Releasing `quickfix-tls 1.16.0` would assert an equivalence that is not true, and
  since the import name is `quickfix` and this is advertised as a drop-in replacement,
  that is exactly the confusion to avoid. PyPI versions can never be reused, so it
  cannot be corrected afterwards.
- **Start the fork counter at `.1`, never `.0`.** PEP 440 zero-pads the release
  segment, so `1.16.0.0` compares *equal* to `1.16.0` rather than above it.
- **Do not use a `+local` suffix** such as `1.16.0+tls.1`. It is valid PEP 440 and
  parses fine locally, but PyPI rejects local version identifiers on upload.

`configure.ac` and `CMakeLists.txt` carry upstream's engine version (currently 1.16.0)
and should be left alone - they describe the C++ engine, not this distribution. Only
`pyproject.toml` carries the fork revision.

Earlier revisions of this document suggested a `.postN` suffix for fork-only changes.
That is discouraged: PEP 440 reserves post-releases for corrections that do not affect
the distributed software, whereas this fork ships different C++ and different build
flags.

## Dry run first (recommended)

A version number can never be reused on PyPI, so rehearse on TestPyPI before the real
thing. Set a throwaway `0.0.0.devN` in `pyproject.toml` on the dry-run branch and tag it
`v0.0.0.devN`: the version published comes from `pyproject.toml`, not from the tag, so
without this the rehearsal uploads the real release version and burns it on TestPyPI.
`.devN` is valid PEP 440 and sorts below every real release. See the
`dry-run-release` command for the full procedure. Register a second trusted publisher for `quickfix-tls` on
[test.pypi.org](https://test.pypi.org/) with environment `testpypi`, then temporarily add
to the publish step:

```yaml
        with:
          repository-url: https://test.pypi.org/legacy/
```

Install the result and confirm it is a real SSL build:

```bash
pip install --index-url https://test.pypi.org/simple/ quickfix-tls
python tools/verify_wheel.py
```

## Grabbing a wheel before a real release

The `github_release` job in `wheels.yml` runs only on manual dispatch
(`workflow_dispatch`, via the Actions tab or `gh workflow run wheels.yml --ref <branch>`).
It publishes that run's wheels + sdist as assets on a disposable **prerelease** tagged
`test-wheels-<run id>` on the repo's Releases page - independent of `publish`, so it
never touches PyPI/TestPyPI and never needs a `v*` tag. It's throwaway by design: a
fresh tag every run, so don't rely on any one of them persisting; delete old ones with
`gh release delete <tag>` when they pile up.

## Releasing

1. Confirm CI is green on `master`, including the `Build wheels` workflow.
2. Set the version in `pyproject.toml` - see **Versioning** below.
3. Tag and push. The tag must match `pyproject.toml` exactly - the publish job
   checks this and fails if they differ, because the version actually uploaded comes
   from `pyproject.toml`, not from the tag:

   ```bash
   git tag -a v1.16.0.1 -m "quickfix-tls 1.16.0.1"
   git push origin v1.16.0.1
   ```

4. The workflow builds **cp39-cp314** on six native runners - manylinux x86_64 and
   aarch64, win_amd64 and win_arm64, macOS x86_64 and arm64 - plus a free-threaded
   lane (`cp313t`, `cp314t`). It skips win32, i686, musllinux, PyPy, and win_arm64 for
   cp39/cp310. Each wheel is checked with `tools/verify_wheel.py`; an sdist is built
   alongside, and the publish job uploads everything.

The verify step is the gate that matters: it constructs each SSL transport, so a wheel
that was accidentally built without OpenSSL fails the build instead of being published.
Checking that the SSL classes merely *exist* would not catch it - they exist either way.

## After a release

Confirm the wheel actually solves the problem it exists for - installing without a
compiler:

```bash
pip install quickfix-tls
python -c "import quickfix; quickfix.ThreadedSSLSocketInitiator"
```

## Upstream

The ThreadedSSL exposure in this fork is offered upstream at
[quickfix/quickfix](https://github.com/quickfix/quickfix). If it is accepted and the
project starts publishing wheels, this package should be deprecated on PyPI rather than
left to drift.
