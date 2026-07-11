#!/usr/bin/env bash
#
# mayhem/test.sh — RUN fio's own CUnit unit-test suite (PATCH-grade functional oracle).
#
# mayhem/build.sh built unittests/unittest with NORMAL flags (no SANITIZER_FLAGS / libFuzzer), so it
# won't false-fail on benign UB. This only runs it (lib/oslib/cgroup suites) and maps CUnit's
# "Run Summary" tests row to a CTRF summary. Requires libcunit1-dev (installed in mayhem/Dockerfile).
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
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

# Run the unit-test binary built by mayhem/build.sh (normal flags). Do NOT rebuild here.
BIN=./unittests/unittest
[ -x "$BIN" ] || { echo "missing $BIN — run mayhem/build.sh first" >&2; exit 2; }
out="$("$BIN" 2>&1)"
echo "$out"

# CUnit "Run Summary" tests row: "tests  <Total> <Ran> <Passed> <Failed> <Inactive>"
read -r total ran passed failed < <(awk '/^[[:space:]]*tests[[:space:]]/ {print $2, $3, $4, $5}' <<<"$out")
: "${total:=0}" "${ran:=0}" "${passed:=0}" "${failed:=0}"
skipped=$(( total > ran ? total - ran : 0 ))   # inactive (registered but not run)

emit_ctrf "cunit" "$passed" "$failed" "$skipped"
