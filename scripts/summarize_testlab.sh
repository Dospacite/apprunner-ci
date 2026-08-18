#!/usr/bin/env bash
# Condenses gcloud's Test Lab output into a rail line.
#
# gcloud reports the result as a box-drawn table rather than prose:
#   │ Passed  │ iphonese3-26.3-en_US-portrait │ 1 test cases passed │
# so the outcome and the case count are read from that row.
set -euo pipefail
LOG="${1:?usage: summarize_testlab.sh <log>}"

[[ -f "$LOG" ]] || { echo "Test Lab produced no output."; exit 0; }

strip() { sed 's/\x1b\[[0-9;]*m//g' "$LOG"; }

DEVICE="$(strip | sed -nE 's/.*device: model=([^,]+),version=([^,]+).*/\1 on iOS \2/p' | head -1)"

# The result row is the one naming a test axis; its first cell is the outcome
# and its last carries the case tally.
ROW="$(strip | grep -E '^\s*│\s*(Passed|Failed|Skipped|Inconclusive)\s*│' | head -1 || true)"

if [[ -n "$ROW" ]]; then
  OUTCOME="$(awk -F'│' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' <<<"$ROW")"
  DETAILS="$(awk -F'│' '{gsub(/^[ \t]+|[ \t]+$/, "", $4); print $4}' <<<"$ROW")"
  SUMMARY="${DETAILS:-$OUTCOME}"
  # "Test failed to run" is the signature of a rejected or unsignable bundle,
  # not of a test that ran and disagreed with the app.
  if [[ "$DETAILS" == "Test failed to run" ]]; then
    SUMMARY="Test failed to run — the bundle did not launch on the device"
  fi
elif strip | grep -q 'Xctest testing complete'; then
  SUMMARY="Test Lab finished without reporting an outcome"
else
  SUMMARY="Test Lab did not complete"
fi

if [[ -n "$DEVICE" ]]; then
  echo "${SUMMARY} — ${DEVICE}."
else
  echo "${SUMMARY}."
fi
