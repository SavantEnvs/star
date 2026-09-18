#!/usr/bin/env bash
#
# mayhem/build.sh — builds:
#
#   build/STAR                     sanitized STAR binary       -> Mayhem target `star-buggy-mhh-run-20`
#   build-oracle/oracle_seqfuns    clean (unsanitized) build   -> behavioral oracle for mayhem/test.sh
#
# The ORIGINAL mayhemheroes run 20 fuzzed the real /STAR CLI in blackbox mode
# (`/STAR --genomeDir test --genomeFastaFiles @@ --runMode genomeGenerate`), not
# source/SequenceFuns.cpp — so this backport ports THAT harness to v2 (BACKPORT.md's
# "reconstruct the original harness" note), building STAR via its own source/Makefile (`make STAR`,
# the same recipe upstream's own CI runs) with $SANITIZER_FLAGS/$DEBUG_FLAGS layered on through the
# Makefile's documented CXXFLAGSextra/LDFLAGSextra hooks — no Makefile edits. source/htslib (vendored)
# builds with its own unsanitized flags; it's a dependency, not the fuzzed code.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${CXX:=clang++}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX MAYHEM_JOBS COVERAGE_FLAGS

cd "${SRC:-/mayhem}"

STD="-std=c++11"
INC="-I source -fopenmp"
LIB="source/SequenceFuns.cpp"   # oracle's TU (self-contained: only IncludeDefine.h + libc/libc++)

mkdir -p build build-oracle   # the target writes its --genomeDir / Log.out under /tmp at run time

# Build-time LeakSanitizer off-switch (SPEC.md §6.2 item 15), linked into the fuzzed binary. STAR
# never frees its genome/suffix-array buffers before exit, so without this LSan reports ~1.5 GB
# "leaked" on nearly every input and every single test looks like a crash. ASan/UBSan stay on.
# shellcheck disable=SC2086
$CXX $STD -c $SANITIZER_FLAGS $DEBUG_FLAGS -w mayhem/lsan_off.cc -o build/lsan_off.o

pids=()
# The Mayhem target: the real STAR binary, sanitized, built via STAR's own Makefile.
# shellcheck disable=SC2086
(
  cd source
  rm -f Depend.list parametersDefault.xxd STAR
  make -j"$MAYHEM_JOBS" STAR CXX="$CXX" \
      CXXFLAGSextra="$SANITIZER_FLAGS $DEBUG_FLAGS $COVERAGE_FLAGS -w" \
      LDFLAGSextra="$SANITIZER_FLAGS $DEBUG_FLAGS -w ../build/lsan_off.o"
  cp STAR ../build/STAR
) & pids+=($!)

# Oracle: clean build (no sanitizers) so mayhem/test.sh is an honest behavioral check.
# shellcheck disable=SC2086
$CXX $STD -O2 $COVERAGE_FLAGS -w $INC \
    mayhem/oracle_seqfuns.cpp $LIB -o build-oracle/oracle_seqfuns & pids+=($!)

rc=0; for p in "${pids[@]}"; do wait "$p" || rc=1; done
[ "$rc" -eq 0 ] || { echo "build.sh: a target failed to build" >&2; exit 1; }

echo "build.sh: built build/STAR, build-oracle/oracle_seqfuns"
