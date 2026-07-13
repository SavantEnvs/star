# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile (SMALL form) — builds ON TOP of the org C/C++ base image
# (ghcr.io/mayhemheroes/base), which already provides debian + clang/llvm + libFuzzer/afl++ +
# the mayhem identity + the build-contract ENV. This only adds the per-commit build.
#
# Build (from the repo root):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) -t star-commit:test .

FROM ghcr.io/mayhemheroes/base:20260621

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (available to build.sh); do NOT bake it as an ENV — an empty value
# breaks clang. build.sh unsets it when empty.
ARG SOURCE_DATE_EPOCH
# Undefaulted so the base ENV flows through unless overridden with --build-arg.
ARG SANITIZER_FLAGS
ARG COVERAGE_FLAGS=
ARG MAYHEM_JOBS=

# STAR's IncludeDefine.h pulls in <omp.h>; install libomp-dev so clang can find the header + libomp
# (SequenceFuns.cpp itself uses no OpenMP pragmas, but the header must resolve). Re-pin apt to
# SOURCE_DATE_EPOCH first for reproducibility (repro-sources-list.sh ships in the base).
USER root
RUN { [ -n "${SOURCE_DATE_EPOCH:-}" ] && repro-sources-list.sh || true; } \
 && apt-get update && apt-get install -yq --no-install-recommends libomp-dev \
 && rm -rf /var/lib/apt/lists/*

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh

# Run the authored behavioral oracle at build time; a failing oracle fails the image build.
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — repo ships no functional tests"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
