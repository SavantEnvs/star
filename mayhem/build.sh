#!/usr/bin/env bash
#
# mayhem/build.sh — build STAR's `seqfuns` fuzz target + its known-answer oracle.
#
#   build/fuzz_seqfuns             sanitized + libFuzzer   -> Mayhem target `seqfuns`
#   build/fuzz_seqfuns-standalone  sanitized + StandaloneFuzzTargetMain -> crash reproducer
#   build-oracle/oracle_seqfuns    normal flags            -> behavioral oracle for mayhem/test.sh
#
# STAR's read pipeline funnels every base through source/SequenceFuns.cpp (nucleotide<->number
# conversion, complement / reverse-complement, BAM packing, 2-bit int packing, the local-search /
# Hamming aligners, quality splitting). That translation unit is self-contained (only IncludeDefine.h
# + libc/libc++), so we compile it straight in — no htslib, no genome, no network, no upstream edits.
# Idempotent (fixed output paths, overwritten each run) and air-gapped (no fetches).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${CXX:=clang++}"
: "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE STANDALONE_FUZZ_MAIN MAYHEM_JOBS COVERAGE_FLAGS

cd "${SRC:-/mayhem}"

STD="-std=c++11"
# STAR's IncludeDefine.h includes <omp.h>; -fopenmp lets clang resolve it (no OpenMP pragmas are used
# in the harnessed TU, so this only affects header resolution + libomp link, both present in-image).
INC="-I source -fopenmp"
LIB="source/SequenceFuns.cpp"   # the harnessed TU (instrumented, so bugs inside it surface)

mkdir -p build build-oracle

pids=()
# libFuzzer target: SequenceFuns.cpp compiled WITH sanitizers so ASan/UBSan instrument the code.
# $DEBUG_FLAGS after the sanitizer flags so -gdwarf-3 wins (DWARF < 4); -w silences upstream warnings.
# shellcheck disable=SC2086
$CXX $STD $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE -w $INC \
    mayhem/fuzz_seqfuns.cpp $LIB -o build/fuzz_seqfuns & pids+=($!)

# Standalone reproducer: same code path driven by the StandaloneFuzzTargetMain entry (file args).
# The entry is C (declares LLVMFuzzerTestOneInput without extern "C"); compile it AS C with $CC so the
# call keeps C linkage matching the harness's `extern "C"` definition, then link with $CXX.
# shellcheck disable=SC2086
( $CC -c $SANITIZER_FLAGS $DEBUG_FLAGS -w "$STANDALONE_FUZZ_MAIN" -o build/stdmain.o \
  && $CXX $STD $SANITIZER_FLAGS $DEBUG_FLAGS -w $INC \
       mayhem/fuzz_seqfuns.cpp $LIB build/stdmain.o -o build/fuzz_seqfuns-standalone ) & pids+=($!)

# Oracle: clean build (no sanitizers/fuzzer) so mayhem/test.sh is an honest behavioral check.
# shellcheck disable=SC2086
$CXX $STD -O2 $COVERAGE_FLAGS -w $INC \
    mayhem/oracle_seqfuns.cpp $LIB -o build-oracle/oracle_seqfuns & pids+=($!)

rc=0; for p in "${pids[@]}"; do wait "$p" || rc=1; done
[ "$rc" -eq 0 ] || { echo "build.sh: a target failed to build" >&2; exit 1; }

echo "build.sh: built build/fuzz_seqfuns, build/fuzz_seqfuns-standalone, build-oracle/oracle_seqfuns"
