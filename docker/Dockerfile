# A development container carrying the toolchain this project needs.
#
# The point is a local build loop. Without this image there is none: the usual
# host has g++ and make but no cmake, ninja, ruby, swig or libssl-dev, and
# installing them needs root -- so every check became a CI round-trip, and the
# history is full of hypotheses pushed to CI because nothing could be probed
# locally.
#
# It carries three things that are otherwise unavailable:
#   * cmake/ninja/libssl-dev  -- `ctest -L unit` in seconds
#   * ruby                    -- `cpp.acceptance`, which is Ruby-driven
#   * SWIG 4.2.1              -- regenerating the bindings at the pinned version
#
# and a mingw-w64 + Wine cross lane for smoke-testing Windows code. That lane is
# a first-pass filter only: Wine is not Windows, and the MSVC CI legs remain the
# authority for anything that ships.
FROM ubuntu:24.04

# Must match the SWIG_VERSION in .github/workflows/swig.yml and the version
# recorded in the committed wrapper. A different SWIG rewrites all 5.86 MB of
# src/python/QuickfixPython.cpp, which the drift job then fails on.
ARG SWIG_VERSION=4.2.1

ARG UID=1000
ARG GID=1000

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential cmake ninja-build pkg-config git curl ca-certificates \
      libssl-dev \
      python3 python3-dev python3-venv python3-pip \
      ruby \
      bison libpcre2-dev \
      mingw-w64 \
      wine wine64 \
      xz-utils file \
    && rm -rf /var/lib/apt/lists/*

# SWIG from source, not apt: distro packages drift, and this version has to match
# the committed wrapper exactly. SourceForge rather than GitHub because swig/swig
# publishes no release assets and the git archive has no configure script.
RUN curl -fsSL -o /tmp/swig.tar.gz \
      "https://downloads.sourceforge.net/project/swig/swig/swig-${SWIG_VERSION}/swig-${SWIG_VERSION}.tar.gz" \
    && tar xzf /tmp/swig.tar.gz -C /tmp \
    && cd "/tmp/swig-${SWIG_VERSION}" \
    && ./configure --prefix=/opt/swig \
    && make -j"$(nproc)" \
    && make install \
    && rm -rf /tmp/swig*
ENV PATH="/opt/swig/bin:${PATH}"

# A static OpenSSL cross-built for Windows, baked in because it is slow and
# never changes between builds.
#
# Built by the repo's own script rather than by an inlined recipe, so the
# version and checksum live in exactly one place. A second OpenSSL version in
# this repo is the drift PR #10 closed; do not reintroduce it here.
COPY tools/setup_openssl.sh /tmp/setup_openssl.sh
RUN OPENSSL_CROSS_MINGW=1 OPENSSL_ROOT_DIR=/opt/openssl-mingw \
      bash /tmp/setup_openssl.sh \
    && rm -f /tmp/setup_openssl.sh
ENV OPENSSL_MINGW_ROOT=/opt/openssl-mingw

# clang-format at the exact version .github/workflows/format.yml gates on, so
# the check can be run before pushing rather than after. From PyPI (prebuilt
# binaries, exact versions) rather than apt, whose clang-format is 18 here --
# and a different major version reformats differently, which would make a local
# "clean" mean nothing.
ARG CLANG_FORMAT_VERSION=22.1.5
RUN python3 -m venv /opt/clang-format \
    && /opt/clang-format/bin/pip install --no-cache-dir "clang-format==${CLANG_FORMAT_VERSION}"
ENV PATH="/opt/clang-format/bin:${PATH}"

# Run as the host user. The repo is bind-mounted, so a root container would
# leave root-owned build trees behind on the host.
RUN if ! getent group ${GID} >/dev/null; then groupadd -g ${GID} dev; fi \
    && if ! getent passwd ${UID} >/dev/null; then \
         useradd -m -u ${UID} -g ${GID} -s /bin/bash dev; \
       fi \
    && install -d -o ${UID} -g ${GID} /home/dev
USER ${UID}:${GID}
ENV HOME=/home/dev

# Initialise the Wine prefix at build time. The first wineboot is slow and
# writes state; doing it here keeps it out of the first ctest run.
ENV WINEPREFIX=/home/dev/.wine
ENV WINEDEBUG=-all
# `wineserver -k`, not `-w`: -w waits for the server to exit, and it does not --
# it lingers by design, so the build hangs there. -k kills it, which is what is
# wanted before the layer is committed.
RUN wineboot --init >/dev/null 2>&1 || true; wineserver -k || true

WORKDIR /src
CMD ["/bin/bash"]
