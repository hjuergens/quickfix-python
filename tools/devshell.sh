#!/usr/bin/env bash
# Open a shell in the development container, with the repo bind-mounted.
#
# Builds the image on first use; afterwards it is cached. See docker/Dockerfile
# for what is in it and why.
#
# Usage:
#   tools/devshell.sh                 # interactive shell
#   tools/devshell.sh <command...>    # run one command and exit
#   REBUILD=1 tools/devshell.sh       # force an image rebuild
set -euo pipefail

IMAGE="${QUICKFIX_DEV_IMAGE:-quickfix-dev}"
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)

if [ -n "${REBUILD:-}" ] || ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  echo "== building ${IMAGE} (first build compiles SWIG and OpenSSL; expect ~15 min)" >&2
  docker build \
    --build-arg "UID=$(id -u)" \
    --build-arg "GID=$(id -g)" \
    -t "${IMAGE}" \
    -f "${REPO_ROOT}/docker/Dockerfile" \
    "${REPO_ROOT}"
fi

# Mount at the same path as on the host so paths in compiler output and in
# CMake caches mean the same thing in both places.
DOCKER_ARGS=(
  --rm
  --user "$(id -u):$(id -g)"
  --volume "${REPO_ROOT}:${REPO_ROOT}"
  --workdir "${REPO_ROOT}"
)
[ -t 0 ] && DOCKER_ARGS+=(--interactive --tty)

if [ "$#" -eq 0 ]; then
  cat >&2 <<'BANNER'
quickfix dev container. Native build:

  cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DHAVE_SSL=ON
  cmake --build build && ctest --test-dir build -L unit --output-on-failure

Windows cross build, run under Wine:

  cmake -S . -B build-mingw -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-mingw-w64.cmake \
        -DCMAKE_BUILD_TYPE=Release -DQUICKFIX_TESTS=ON
  cmake --build build-mingw && ctest --test-dir build-mingw -L unit --output-on-failure

Note: configuring rewrites the TRACKED files src/C++/config.h and
include/quickfix/config.h. Check `git status` before committing.
BANNER
  exec docker run "${DOCKER_ARGS[@]}" "${IMAGE}" /bin/bash
fi

exec docker run "${DOCKER_ARGS[@]}" "${IMAGE}" "$@"
