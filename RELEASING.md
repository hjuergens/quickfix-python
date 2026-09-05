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

## Dry run first (recommended)

A version number can never be reused on PyPI, so rehearse on TestPyPI before the real
thing. Register a second trusted publisher for `quickfix-tls` on
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

## Releasing

1. Confirm CI is green on `master`, including the `Build wheels` workflow.
2. Set the version in `pyproject.toml`. It tracks the upstream QuickFIX version this fork
   is based on; use a `.postN` suffix for fork-only changes that do not correspond to a
   new upstream release.
3. Tag and push:

   ```bash
   git tag -a v1.16.0 -m "quickfix-tls 1.16.0"
   git push origin v1.16.0
   ```

4. The workflow builds wheels for cp39-cp313 on Linux x86_64, Windows x86_64 and macOS
   (x86_64 + arm64), runs `tools/verify_wheel.py` against each, builds an sdist, and
   publishes everything.

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
