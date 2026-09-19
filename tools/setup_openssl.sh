#!/usr/bin/env bash
# Builds a static OpenSSL for wheel builds, pinned to a version this project
# controls rather than whatever the build platform happens to supply.
#
# macOS: Homebrew's arm64 openssl@3 bottle has been observed to require a much
# newer minimum macOS (26.0) than this project targets (11.0), and delocate
# refuses to bundle a shared library that requires a newer OS than the wheel
# declares.
#
# Linux: the manylinux_2_28 image is AlmaLinux 8, whose openssl-devel is 1.1.1k
# -- end of life since September 2023 -- and EL8 has no openssl3 package. A
# wheel pins whatever it was built against, whether it links statically or has
# the .so vendored in by auditwheel, so "the user's distro patches it" is not
# true either way. The alternative is a newer manylinux image, which would move
# the glibc floor from 2.28 to 2.34 and drop Ubuntu 20.04 and RHEL 8 users.
#
# Static (no-shared) on both: nothing for delocate or auditwheel to bundle, so
# the wheel carries no second OpenSSL SONAME beside the one CPython's own ssl
# module already loaded.
set -euo pipefail

OPENSSL_VERSION="3.5.8"
OPENSSL_SHA256="a8f84a39918ec6415ce765d9b429d313ba97b8143169c172e734b9514464f5b2"
PREFIX="${OPENSSL_ROOT_DIR:-/tmp/openssl-static}"

# OpenSSL installs to lib64 on some Linux configurations.
if [ -f "${PREFIX}/lib/libssl.a" ] || [ -f "${PREFIX}/lib64/libssl.a" ]; then
  echo "OpenSSL ${OPENSSL_VERSION} already built at ${PREFIX}, skipping"
  exit 0
fi

WORKDIR=$(mktemp -d)
trap 'rm -rf "${WORKDIR}"' EXIT
cd "${WORKDIR}"

curl -fsSL -o openssl.tar.gz \
  "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz"
if command -v sha256sum >/dev/null 2>&1; then
  echo "${OPENSSL_SHA256}  openssl.tar.gz" | sha256sum -c -
else
  echo "${OPENSSL_SHA256}  openssl.tar.gz" | shasum -a 256 -c -
fi

tar xzf openssl.tar.gz
cd "openssl-${OPENSSL_VERSION}"

case "$(uname -s)" in
Darwin)
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
  JOBS=$(sysctl -n hw.ncpu)
  ;;
Linux)
  case "$(uname -m)" in
    aarch64 | arm64) OPENSSL_TARGET=linux-aarch64 ;;
    *)               OPENSSL_TARGET=linux-x86_64 ;;
  esac
  # -fPIC is required, not cosmetic: these archives are linked into _quickfix,
  # a shared object. Without it the link fails on relocations.
  # no-dso/no-engine keep libcrypto from needing dlopen, which on the glibc 2.28
  # of manylinux_2_28 still lives in a separate libdl that nothing here links.
  ./Configure "${OPENSSL_TARGET}" no-shared no-tests no-dso no-engine -fPIC \
    --prefix="${PREFIX}" --openssldir="${PREFIX}"
  JOBS=$(nproc)
  ;;
*)
  echo "unsupported platform: $(uname -s)" >&2
  exit 1
  ;;
esac

make -j"${JOBS}"
make install_sw
