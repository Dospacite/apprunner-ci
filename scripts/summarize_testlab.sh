#!/usr/bin/env bash
# Condenses gcloud's Test Lab output into a rail line.
set -euo pipefail
LOG="${1:?usage: summarize_testlab.sh <log>}"

[[ -f "$LOG" ]] || { echo "Test Lab produced no output."; exit 0; }

DEVICE="$(sed -nE 's/^\[testlab\] device: model=([^,]+),version=([^,]+).*/\1 on iOS \2/p' "$LOG" | head -1)"

if grep -q 'All tests passed' "$LOG"; then
  RESULT="All tests passed"
elif grep -qE 'Test failed to run|Failures|failed' "$LOG"; then
  RESULT="$(grep -m1 -oE '[0-9]+ test cases? failed' "$LOG" || echo 'Tests failed')"
else
  RESULT="Test Lab finished"
fi

if [[ -n "$DEVICE" ]]; then
  echo "${RESULT} — ${DEVICE}."
else
  echo "${RESULT}."
fi
