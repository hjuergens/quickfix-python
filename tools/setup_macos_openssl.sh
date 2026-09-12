#!/usr/bin/env bash
# Builds a static OpenSSL for macOS wheel builds, pinned to a specific version
# and to this project's MACOSX_DEPLOYMENT_TARGET, instead of relying on
# Homebrew's bottle. Homebrew's arm64 openssl@3 bottle has been observed to
# require a much newer minimum macOS (26.0) than this project targets (11.0),
# and delocate refuses to bundle a shared library that requires a newer OS
# than the wheel declares. Building statically (no-shared) means there is
# nothing for delocate to bundle in the first place, sidestepping the whole
# class of problem rather than chasing whatever floor Homebrew's bottle
# happens to need on a given runner image.
set -euo pipefail

OPENSSL_VERSION="3.5.8"
OPENSSL_SHA256="a8f84a39918ec6415ce765d9b429d313ba97b8143169c172e734b9514464f5b2"
PREFIX="${OPENSSL_ROOT_DIR:-/tmp/openssl-static}"

if [ -f "${PREFIX}/lib/libssl.a" ]; then
  echo "OpenSSL ${OPENSSL_VERSION} already built at ${PREFIX}, skipping"
  exit 0
fi

WORKDIR=$(mktemp -d)
trap 'rm -rf "${WORKDIR}"' EXIT
cd "${WORKDIR}"

curl -fsSL -o openssl.tar.gz \
  "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz"
echo "${OPENSSL_SHA256}  openssl.tar.gz" | shasum -a 256 -c -

tar xzf openssl.tar.gz
cd "openssl-${OPENSSL_VERSION}"

# cibuildwheel does NOT apply its `environment` table (where
# MACOSX_DEPLOYMENT_TARGET is set for the actual build phase) to `before-all` -
# only to the build/test steps - so that variable is never set here regardless
# of pyproject.toml. Hardcode the same per-arch floor directly instead of
# silently falling through to a mismatched default.
case "$(uname -m)" in
  arm64) OPENSSL_TARGET=darwin64-arm64-cc;    TARGET_MIN="11.0" ;;
  *)     OPENSSL_TARGET=darwin64-x86_64-cc;   TARGET_MIN="10.15" ;;
esac

./Configure "${OPENSSL_TARGET}" no-shared no-tests \
  "-mmacosx-version-min=${TARGET_MIN}" \
  --prefix="${PREFIX}" --openssldir="${PREFIX}"

make -j"$(sysctl -n hw.ncpu)"
make install_sw
