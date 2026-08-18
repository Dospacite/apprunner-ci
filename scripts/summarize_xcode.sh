#!/usr/bin/env bash
# Pulls the first real xcodebuild error out of a build log for the rail.
set -euo pipefail
LOG="${1:?usage: summarize_xcode.sh <log>}"

[[ -f "$LOG" ]] || { echo "The iOS build produced no output."; exit 0; }

# Xcode prints the actionable line as "error: ..."; the surrounding noise is
# not worth showing on a one-line rail entry.
LINE="$(grep -m1 -oE '(error|fatal error): .*' "$LOG" | head -1 || true)"
[[ -n "$LINE" ]] || LINE="$(grep -m1 -E '\*\* BUILD FAILED \*\*|Exception|Error:' "$LOG" || true)"
[[ -n "$LINE" ]] || LINE="The iOS build failed; see the log."

echo "${LINE:0:300}"
