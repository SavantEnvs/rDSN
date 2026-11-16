#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# Runs rDSN's own gtest suite the way upstream's bin/Linux/test.sh does: for every module's test
# dir, run dsn.svchost once per config listed in its `gtests` file. Each config sets `[core] gtest =
# true`, so unit_test_driver.cpp runs the module's cases inside the live runtime (asio TCP/UDP
# networking on localhost ports, aio, nfs, the emulator) and dsn_exit()s with RUN_ALL_TESTS's result.
# The gtest PASSED/FAILED counts of every run are summed into one CTRF report.
SUITE="$SRC/mayhem/build/suite"
SVC_HOST="$SUITE/dsn.svchost"
[ -x "$SVC_HOST" ] || { echo "missing $SVC_HOST: mayhem/build.sh did not build it" >&2; emit_ctrf "gtest" 0 1 0; exit 1; }
export LD_LIBRARY_PATH="$SUITE${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

TEST_DIRS="src/core/src/test src/plugins/tools.common/test src/plugins/tools.emulator/test
  src/plugins/tools.nfs/test src/plugins/dist.uri.resolver/test"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/rdsn-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
PASSED=0; FAILED=0
for d in $TEST_DIRS; do
  [ -f "$SRC/$d/gtests" ] || { echo "missing $d/gtests" >&2; FAILED=$((FAILED + 1)); continue; }
  # The tests write data/log files into their cwd: run each module from a scratch copy of its dir.
  w="$WORK/$(echo "$d" | tr / _)"
  mkdir -p "$w" && cp -r "$SRC/$d/." "$w/"
  while read -r line || [ -n "$line" ]; do
    line=$(echo "$line" | tr -d '[:space:]')
    case "$line" in ""|\#*) continue ;; esac
    echo "============ $d: dsn.svchost $line ============"
    log="$w/$line.gtest.log"
    (cd "$w" && rm -rf ./data core && "$SVC_HOST" "$w/$line") >"$log" 2>&1
    rc=$?
    p=$(sed -n 's/^\[  PASSED  \] \([0-9][0-9]*\) tests\{0,1\}\..*/\1/p' "$log" | tail -n1)
    f=$(sed -n 's/^\[  FAILED  \] \([0-9][0-9]*\) tests\{0,1\}, listed below.*/\1/p' "$log" | tail -n1)
    grep -E '^\[  (PASSED|FAILED)  \]|^\[==========\] .* ran' "$log" || true
    # A crash, a non-zero exit, or a run that never reached gtest's summary is a failure.
    if [ -z "$p" ] && [ -z "$f" ]; then
      echo "$d/$line: no gtest summary (exit $rc)" >&2; tail -n 20 "$log" >&2; f=1
    elif [ "$rc" -ne 0 ] && [ "${f:-0}" -eq 0 ]; then
      echo "$d/$line: exit $rc" >&2; tail -n 20 "$log" >&2; f=1
    fi
    PASSED=$((PASSED + ${p:-0})); FAILED=$((FAILED + ${f:-0}))
  done < "$SRC/$d/gtests"
done

# bin/Linux/test.sh's second loop runs every bin/*/test.sh; src/tests/idl's is `./dsn.idl.tests`
# (thrift binary/JSON serialization round-trips + golden JSON). Its main forces the thrift_helper
# cases; ours leaves out the 3 *code_generation* ones (they need the thrift compiler + a CMake build
# at test time). js_runtime_compatibility is only compiled with Node >= 18, which the image lacks.
IDL_TESTS="$SUITE/dsn.idl.tests"
w="$WORK/src_tests_idl"; log="$w/dsn.idl.tests.log"
mkdir -p "$w" && cp -r "$SRC/src/tests/idl/." "$w/"
echo "============ src/tests/idl: dsn.idl.tests ============"
if [ -x "$IDL_TESTS" ]; then
  (cd "$w" && DSN_TEST_TMP_DIR="$w/tmp" "$IDL_TESTS") >"$log" 2>&1
  rc=$?
else
  echo "missing $IDL_TESTS: mayhem/build.sh did not build it" >"$log"; rc=127
fi
p=$(sed -n 's/^\[  PASSED  \] \([0-9][0-9]*\) tests\{0,1\}\..*/\1/p' "$log" | tail -n1)
f=$(sed -n 's/^\[  FAILED  \] \([0-9][0-9]*\) tests\{0,1\}, listed below.*/\1/p' "$log" | tail -n1)
grep -E '^\[  (PASSED|FAILED)  \]|^\[==========\] .* ran' "$log" || true
if [ -z "$p" ] && [ -z "$f" ]; then
  echo "src/tests/idl: no gtest summary (exit $rc)" >&2; tail -n 20 "$log" >&2; f=1
elif [ "$rc" -ne 0 ] && [ "${f:-0}" -eq 0 ]; then
  echo "src/tests/idl: exit $rc" >&2; tail -n 20 "$log" >&2; f=1
fi
PASSED=$((PASSED + ${p:-0})); FAILED=$((FAILED + ${f:-0}))

emit_ctrf "gtest" "$PASSED" "$FAILED" 0
