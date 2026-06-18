#!/usr/bin/env bash
#
# prepare_batches.sh — stage the corpus whitelist for batch validation.
#
# Step 1: copy test/corpus/accepted_findings.txt into this tool's directory.
# Step 2: split its FINDINGS (the header comment block and blank lines are
#         stripped) into fixed-size batch files under data/ — one validation
#         unit per file.
#
# Re-running regenerates everything from scratch: it clears data/ AND reports/
# (batch boundaries shift whenever the whitelist changes, so old reports would
# no longer line up). Run it again only when you want a fresh pass.
#
# Usage:   prepare_batches.sh
# Env:     ROWS_PER_BATCH   findings per batch file (default 100)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR"/../.. && pwd)"

SRC="$REPO/test/corpus/accepted_findings.txt"
COPY="$SCRIPT_DIR/accepted_findings.txt"
DATA="$SCRIPT_DIR/data"
REPORTS="$SCRIPT_DIR/reports"
ROWS_PER_BATCH="${ROWS_PER_BATCH:-100}"

[[ -f "$SRC" ]] || { echo "error: source whitelist not found: $SRC" >&2; exit 1; }

# Step 1 — copy the whitelist verbatim into the tool dir.
cp "$SRC" "$COPY"

# Step 2 — split the findings (no comments/blanks) into 100-row batch files.
rm -rf "$DATA" "$REPORTS"
mkdir -p "$DATA" "$REPORTS"

rows="$DATA/.rows.tmp"
grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$COPY" > "$rows"
total="$(wc -l < "$rows" | tr -d ' ')"

# GNU split: numeric 3-digit suffix → batch_000.txt, batch_001.txt, …
split -l "$ROWS_PER_BATCH" -d -a 3 --additional-suffix=.txt "$rows" "$DATA/batch_"
rm -f "$rows"

n="$(find "$DATA" -name 'batch_*.txt' | wc -l | tr -d ' ')"
echo "[prepare] copied whitelist → $COPY"
echo "[prepare] ${total} findings → ${n} batch file(s) of ${ROWS_PER_BATCH} rows in $DATA"
echo "[prepare] reports will be written to $REPORTS"
