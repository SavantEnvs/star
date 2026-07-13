#!/usr/bin/env bash
#
# mayhem/test.sh — behavioral oracle for STAR's core sequence primitives. RUNS the prebuilt clean
# binary build-oracle/oracle_seqfuns (from mayhem/build.sh); never compiles. The oracle asserts EXACT
# outputs of source/SequenceFuns.cpp — the same routines the `seqfuns` fuzz target drives — so a
# neutered/exit(0) program produces no RESULT marker and FAILS here (not reward-hackable). Emits a
# CTRF (ctrf.io) summary and exits non-zero on any failure.
#
# NOTE ON THE UPSTREAM SUITE: alexdobin/STAR ships NO runnable unit/functional test suite. Its build
# (.travis.yml) only compiles the aligner (`cd source && make STAR`); extras/tests/ holds a few awk
# post-processing helpers (checkCellReadsStats*.awk) with no harness, expected outputs, or runner, and
# STARsolo full-pipeline tests require multi-GB genomes/reads fetched over the network. There is thus
# nothing meaningful to run offline. We therefore report tests_found=0 for the upstream suite and
# provide this authored known-answer oracle as the strongest available behavioral regression check.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "${SRC:-/mayhem}"

emit_ctrf() {
  local tool="$1" p="$2" f="$3" s="${4:-0}"; local tests=$(( p + f + s ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": { "tests": $tests, "passed": $p, "failed": $f, "pending": 0, "skipped": $s, "other": 0 }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":0,"skipped":%d,"other":0}}}\n' \
    "$tool" "$tests" "$p" "$f" "$s"
  [ "$f" -eq 0 ]
}

ORACLE=build-oracle/oracle_seqfuns
if [ ! -x "$ORACLE" ]; then
  echo "test.sh: oracle binary missing — build.sh must build $ORACLE (not rebuilding here)" >&2
  emit_ctrf star-seqfuns 0 1; exit 1
fi

out="$("$ORACLE" 2>&1)"; rc=$?
echo "$out"

# Parse the oracle's own RESULT marker. Absent (neutered / crashed) => hard fail.
line="$(grep -oE 'RESULT passed=[0-9]+ failed=[0-9]+' <<<"$out" | tail -1)"
if [ -z "$line" ]; then
  echo "test.sh: oracle produced no RESULT marker (binary neutered or crashed, rc=$rc)" >&2
  emit_ctrf star-seqfuns 0 1; exit 1
fi

passed="$(sed -E 's/.*passed=([0-9]+).*/\1/' <<<"$line")"
failed="$(sed -E 's/.*failed=([0-9]+).*/\1/' <<<"$line")"
echo "test.sh: passed=$passed failed=$failed (rc=$rc)"
emit_ctrf star-seqfuns "$passed" "$failed"
