#!/usr/bin/env bash
#
# mayhem/test.sh — RUN can-utils' functional checks (binaries built by mayhem/build.sh, normal flags):
#   * asc2log / log2asc: fixed input files -> asserted golden output (mayhem/kat/*.expected.*)
#   * kat_canframe: parse_canframe / snprintf_canframe / snprintf_long_canframe known-answer table
# Every assertion compares real program output, so a program that exits 0 without doing its job fails.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"
export LC_ALL=C TZ=UTC

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

passed=0
failed=0
K=mayhem/kat

for bin in asc2log log2asc kat_canframe; do
  [ -x "$SRC/$bin" ] || { echo "missing $SRC/$bin: mayhem/build.sh must build it" >&2; emit_ctrf can-utils-kat 0 1; exit 1; }
done

# check <name> <expected-file> <actual-output-file>
check() {
  if [ -s "$3" ] && cmp -s "$2" "$3"; then
    echo "PASS $1"; passed=$((passed + 1))
  else
    echo "FAIL $1"; diff "$2" "$3" | head -10; failed=$((failed + 1))
  fi
}

out=$(mktemp)
trap 'rm -f "$out"' EXIT

for t in rel_hex rel_dec rel_fd; do
  "$SRC/asc2log" -I "$K/$t.asc" > "$out" 2>/dev/null
  check "asc2log $t" "$K/$t.expected.log" "$out"
done

"$SRC/log2asc" -I "$K/in.log" vcan0 2>/dev/null | grep -E '^ +[0-9]' > "$out"
check "log2asc in.log" "$K/in.expected.asc" "$out"

# round trip: log -> asc -> log keeps frames (timestamps are re-based by log2asc, so compare frames only)
"$SRC/log2asc" -I "$K/in.log" vcan0 2>/dev/null > "$out.asc"
"$SRC/asc2log" -I "$out.asc" 2>/dev/null | sed -e 's/^([0-9.]*) can0 //' -e 's/ R$//' > "$out"
rm -f "$out.asc"
printf '%s\n' '044#2A366C2BBA' '236#C3406B6A1A1E2C' '1F334455#1122334455667788' '123#R' '123##5112233' > "$out.want"
check "log2asc|asc2log round trip" "$out.want" "$out"
rm -f "$out.want"

kat_out=$("$SRC/kat_canframe" 2>&1); kat_rc=$?
echo "$kat_out"
if summary=$(printf '%s\n' "$kat_out" | grep -E '^KAT: [0-9]+ run; [0-9]+ failed$'); then
  run=$(printf '%s' "$summary" | sed -E 's/^KAT: ([0-9]+) run.*/\1/')
  bad=$(printf '%s' "$summary" | sed -E 's/^KAT: [0-9]+ run; ([0-9]+) failed$/\1/')
  [ "$kat_rc" -eq 0 ] || [ "$bad" -gt 0 ] || bad=1
  passed=$((passed + run - bad)); failed=$((failed + bad))
else
  echo "FAIL kat_canframe produced no summary"; failed=$((failed + 1))
fi

emit_ctrf can-utils-kat "$passed" "$failed"
