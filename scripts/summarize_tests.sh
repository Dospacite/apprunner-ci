#!/usr/bin/env bash
# Turns a `flutter test` log into the one line the pipeline rail shows.
set -euo pipefail
LOG="${1:?usage: summarize_tests.sh <log>}"

[[ -f "$LOG" ]] || { echo "No test output was captured."; exit 0; }

# The expanded reporter ends every line with "+passed -failed ~skipped: message".
TALLY="$(grep -oE '\+[0-9]+( -[0-9]+)?( ~[0-9]+)?:' "$LOG" | tail -1 | tr -d ':')"
PASSED="$(sed -nE 's/.*\+([0-9]+).*/\1/p' <<<"${TALLY:-}")"
FAILED="$(sed -nE 's/.*-([0-9]+).*/\1/p' <<<"${TALLY:-}")"

if [[ -z "${PASSED:-}" ]]; then
  if grep -q 'No tests ran' "$LOG"; then
    echo "No tests ran."
  else
    echo "Test run produced no tally; see the log."
  fi
  exit 0
fi

if [[ -n "${FAILED:-}" && "$FAILED" -gt 0 ]]; then
  echo "${FAILED} failed, ${PASSED} passed."
else
  echo "${PASSED} tests passed."
fi
