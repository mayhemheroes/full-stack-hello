#!/usr/bin/env bash
# full-stack-hello/mayhem/test.sh — RUN the project's OWN golden-output test suite against the
# normal-flags `as_exec` that mayhem/build.sh produced → CTRF. PATCH-grade oracle: it never compiles.
#
# The suite is the project's tests/*.s / tests/*.expected pairs (the same cases the upstream Makefile's
# `check`/`test` targets and tests/runner.py drive): each tests/<name>.s is assembled+executed by
# as_exec and its stdout is asserted EQUAL to the golden tests/<name>.expected. This is a KNOWN-ANSWER
# / golden-output suite — it asserts the assembler+VM produce the exact documented output (e.g. hello.s
# prints "Hello World", halt.s prints "42", mul.s the multiplication results), NOT merely that the
# binary exits 0. A no-op / exit(0) "patch" to as_exec prints nothing and FAILS every diff, so it
# cannot reward-hack this oracle.
#
# We diff stdout directly rather than invoke tests/runner.py: runner.py targets Python 2 (its
# `f.strip('.s')` would mangle names like `coverage.s` -> `coverage` only by luck and breaks under
# Python 3 semantics) and hard-codes `./as_exec`; running the golden diff here is the same assertion,
# robust, and points at the normal-flags oracle build.sh produced.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
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

AS_EXEC="$SRC/build-tests/as_exec"
[ -x "$AS_EXEC" ] || { echo "missing $AS_EXEC — run mayhem/build.sh first" >&2; exit 2; }

passed=0; failed=0
for s in "$SRC"/tests/*.s; do
  exp="${s%.s}.expected"
  [ -f "$exp" ] || continue          # only cases that ship a golden file are known-answer tests
  name="$(basename "${s%.s}")"
  got="$("$AS_EXEC" "$s" 2>/dev/null)" || true
  if [ "$got" = "$(cat "$exp")" ]; then
    passed=$((passed+1))
  else
    failed=$((failed+1))
    echo "FAIL: $name (output != $exp)" >&2
  fi
done

echo "full-stack-hello golden suite: passed=$passed failed=$failed" >&2
emit_ctrf "full-stack-hello-golden" "$passed" "$failed"
