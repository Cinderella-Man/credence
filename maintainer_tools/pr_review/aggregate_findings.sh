#!/usr/bin/env bash
# Build a committed, reviewable digest of the append-only findings ledger.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/manifest.json"
FINDINGS="$SCRIPT_DIR/findings.md"
JSON="$SCRIPT_DIR/finding_summary.json"
MARKDOWN="$SCRIPT_DIR/finding_summary.md"
[[ -f "$MANIFEST" && -f "$FINDINGS" ]] || { echo "manifest/findings missing" >&2; exit 1; }

rows="$(mktemp "${TMPDIR:-/tmp}/pr-findings.XXXXXX")"
trap 'rm -f "$rows"' EXIT
awk '
  /^## / { section=$0; sub(/^## /, "", section); sub(/ — .*/, "", section); next }
  /^- (blocker|concern|nit):/ {
    severity=$2; sub(/:$/, "", severity)
    text=$0; sub(/^- [a-z]+: /, "", text)
    printf "%s\t%s\t%s\n", severity, section, text
  }
' "$FINDINGS" > "$rows"

jq -Rn --slurpfile manifest "$MANIFEST" '
  [inputs | split("\t") | select(length >= 3) |
    {severity: .[0], reviewed_path: .[1], finding: (.[2:] | join("\t")),
     signature: ((.[2:] | join("\t"))
       | ascii_downcase
       | gsub("[a-z0-9_./-]+:[0-9]+"; "<anchor>")
       | gsub("[0-9]+"; "#"))}]
  | . as $items
  | {generated_at: (now | todateiso8601),
     reviewed: ([$manifest[0].files[] | select(.status == "done")] | length),
     total: ($manifest[0].files | length),
     counts: {blocker: ([$items[] | select(.severity == "blocker")] | length),
              concern: ([$items[] | select(.severity == "concern")] | length),
              nit: ([$items[] | select(.severity == "nit")] | length)},
     repeated_root_causes: ([$items | group_by(.signature)[] | select(length > 1) |
       {count: length, signature: .[0].signature,
        paths: ([.[].reviewed_path] | unique), findings: [.[].finding]}]
       | sort_by(-.count)),
     items: $items}
' "$rows" > "$JSON.tmp"
mv "$JSON.tmp" "$JSON"

jq -r '
  "# Finding summary\n\nGenerated: \(.generated_at)\n\n" +
  "Progress: \(.reviewed)/\(.total) files reviewed.\n\n" +
  "- Blockers: \(.counts.blocker)\n- Concerns: \(.counts.concern)\n- Nits: \(.counts.nit)\n\n" +
  "## Repeated root-cause candidates\n\n" +
  (if (.repeated_root_causes | length) == 0 then "None detected.\n" else
    (.repeated_root_causes | map("### \(.count) occurrences\n\nPaths: \(.paths | join(", "))\n\nNormalized signature: `\(.signature)`\n") | join("\n")) end) +
  "\n## Blockers\n\n" +
  ([.items[] | select(.severity == "blocker") | "- **\(.reviewed_path)** — \(.finding)"] | if length == 0 then ["None."] else . end | join("\n")) + "\n"
' "$JSON" > "$MARKDOWN.tmp"
mv "$MARKDOWN.tmp" "$MARKDOWN"
echo "wrote ${MARKDOWN##*/} and ${JSON##*/}"
