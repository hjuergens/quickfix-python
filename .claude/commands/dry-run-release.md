Rehearse a `quickfix-tls` release against TestPyPI before ever cutting a real
release, per the "Dry run first" section of [RELEASING.md](../../RELEASING.md).

Usage: /dry-run-release

This exercises two different things, and either can be run independently:

- **Option A — local `twine` upload**: tests that the built wheel/sdist
  actually install and work from TestPyPI. Needs only a TestPyPI account API
  token, no CI changes, no trusted-publisher registration. Does *not* exercise
  the GitHub Actions OIDC trusted-publishing flow `wheels.yml` actually uses
  for a real release — a green Option A run does not prove Option B will work.
- **Option B — full CI dry run**: pushes a throwaway tag and a temporary
  workflow edit to trigger a real GitHub Actions run that publishes to
  test.pypi.org the same way a real release would. Requires the TestPyPI
  trusted publisher to be registered first (see step B1). Does not touch the
  real `pypi` environment or the real project.

Ask the user which one they want if it isn't already clear from context — e.g.
if the TestPyPI trusted publisher isn't registered yet, Option A is the only
one that will work right now.

## Option A: local twine upload

A1. **Build the distributions locally**, matching what CI would produce:
    ```
    pipx run build
    ```
    This drops a wheel and an sdist under `dist/`.

A2. **Get a TestPyPI API token** from the user if not already available
    (test.pypi.org -> account settings -> API tokens). This is a personal
    token used only on the user's machine for this one command — it is never
    committed or added to CI secrets, which would defeat the point of trusted
    publishing.

A3. **Upload**:
    ```
    pipx run twine upload --repository testpypi dist/*
    ```
    `twine` will prompt for the token (username `__token__`, password the
    token itself) unless `TWINE_PASSWORD`/`TWINE_USERNAME` are already set in
    the shell.

A4. **Install and verify** the uploaded package. `--extra-index-url` is
    needed because TestPyPI doesn't mirror this project's dependencies:
    ```
    pip install --index-url https://test.pypi.org/simple/ --extra-index-url https://pypi.org/simple quickfix-tls
    python tools/verify_wheel.py
    ```

A5. **Remember the version is now burned on TestPyPI** — like real PyPI, a
    version number can never be reused there. Bump to a fresh `.devN` suffix in
    `pyproject.toml` for the next dry run rather than re-uploading the same
    version (`.postN` is not appropriate — see Versioning in RELEASING.md).

## Option B: full CI/OIDC dry run

B1. **Check prerequisites before touching anything.**
   - Ask the user to confirm a trusted publisher for `quickfix-tls` is
     registered on [test.pypi.org](https://test.pypi.org/) (account menu ->
     Publishing, or the project's Manage -> Publishing page) with these exact
     values, matching the table in RELEASING.md but for the test index:
     | Field | Value |
     |---|---|
     | PyPI project name | `quickfix-tls` |
     | Owner | `hjuergens` |
     | Repository | `quickfix-python` |
     | Workflow name | `wheels.yml` |
     | Environment name | `testpypi` |
     This can only be verified on test.pypi.org itself — there is no API or
     repo file that reflects it. If the user hasn't done this yet, stop here
     and tell them to register it first (a "pending publisher" if the
     TestPyPI project doesn't exist yet).
   - Check whether the `testpypi` GitHub environment exists:
     ```
     gh api repos/hjuergens/quickfix-python/environments --jq '.environments[].name'
     ```
     If it's missing, create it (mirroring the real `pypi` environment, but a
     required reviewer is optional here since nothing user-facing is at
     stake):
     ```
     gh api -X PUT repos/hjuergens/quickfix-python/environments/testpypi
     ```

B2. **Create a throwaway branch** for the temporary workflow edit — never do
   this directly on `master`:
   ```
   git checkout -b dry-run-testpypi
   ```

B3. **Edit `.github/workflows/wheels.yml`'s `publish` job** to target TestPyPI
   instead of the real index. Two fields change together — changing only the
   `repository-url` without the environment leaves the OIDC claim as `pypi`,
   which won't match a trusted publisher registered for `testpypi`:
   ```yaml
   publish:
     ...
     environment:
       name: testpypi
       url: https://test.pypi.org/p/quickfix-tls
     ...
     steps:
       ...
       - name: Publish
         uses: pypa/gh-action-pypi-publish@v1.14.2
         with:
           repository-url: https://test.pypi.org/legacy/
   ```
   Commit this on the throwaway branch:
   ```
   git add .github/workflows/wheels.yml
   git commit -m "Point publish job at TestPyPI for a dry run"
   ```

B4. **Set a throwaway version on the branch.** `pyproject.toml` carries a static
   `version`, so the tag does not decide what gets published — without this step
   the dry run uploads the *real* release version to TestPyPI and burns it there
   permanently. Use a `.devN` suffix: it is valid PEP 440 (`dryrunN` is not, in
   any spelling) and sorts below every real release, so it can never shadow one.
   ```
   # in pyproject.toml, on the throwaway branch only
   version = "0.0.0.dev1"
   ```
   ```
   git add pyproject.toml .github/workflows/wheels.yml
   git commit -m "Point publish job at TestPyPI for a dry run"
   ```

B5. **Confirm with the user before pushing anything** — this triggers a real,
   billed CI run across 6 OS/arch runners plus the free-threaded lane. Ask for
   an explicit go-ahead, then push the branch and a tag whose name matches the
   version exactly (bump N if a prior dry-run tag exists; a version can never be
   reused even on TestPyPI). The publish job verifies the two agree and fails
   the run if they do not:
   ```
   git push origin dry-run-testpypi
   git tag -a v0.0.0.dev1 -m "TestPyPI dry run" dry-run-testpypi
   git push origin v0.0.0.dev1
   ```

B6. **Watch the run**:
   ```
   gh run watch --exit-status $(gh run list --workflow=wheels.yml --limit 1 --json databaseId --jq '.[0].databaseId')
   ```
   If the `publish` job fails with an OIDC/authentication error, the
   TestPyPI trusted publisher registration is the most likely culprit — recheck
   the table in step 1 for a typo (workflow name and environment name are the
   two easiest to get wrong).

B7. **Verify the published dry-run wheel**:
   ```
   pip install --index-url https://test.pypi.org/simple/ quickfix-tls==0.0.0.dev1
   python tools/verify_wheel.py
   ```
   This is the version set in B4, not a normalization of the tag name — the tag
   only selects the commit.

B8. **Clean up regardless of outcome** — a dry run must never leave a trace on
   `master` or a stray tag lying around:
   - Delete the local and remote dry-run tag:
     ```
     git tag -d v0.0.0.dev1
     git push origin --delete v0.0.0.dev1
     ```
   - Delete the local and remote throwaway branch:
     ```
     git checkout master
     git branch -D dry-run-testpypi
     git push origin --delete dry-run-testpypi
     ```
   - Leave the real `wheels.yml` on `master` untouched — it was never modified,
     only the throwaway branch was.
   - A TestPyPI release can't be deleted once published (same rule as real
     PyPI), so the dry-run version number is burned permanently on the test
     index — that's expected and fine, it's what the test index is for.
