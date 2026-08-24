#!/usr/bin/env bash
# Generate human-sized review packets from the manifest and campaign ledgers.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="$SCRIPT_DIR/manifest.json"
SUMMARY="$SCRIPT_DIR/finding_summary.json"
OUT="$SCRIPT_DIR/merge_packets"
mkdir -p "$OUT"

packet_for() {
  local category="$1" title="$2" file="$OUT/$3.md"
  {
    printf '# %s\n\n' "$title"
    printf 'Candidate: `%s` against `%s`.\n\n' "$(git -C "$REPO" rev-parse --short HEAD)" "$(jq -r .base_branch "$MANIFEST")"
    printf '## Files\n\n'
    jq -r --arg c "$category" '.files[] | select(.category == $c) | "- `\(.path)` — \(.status), verdict: \(.verdict // "not reviewed")"' "$MANIFEST"
    printf '\n## Active findings\n\n'
    jq -r --arg c "$category" --slurpfile m "$MANIFEST" '
      [.items[] as $i | ($m[0].files[] | select(.path == $i.reviewed_path and .category == $c)) | "- **\($i.severity)** `\($i.reviewed_path)` — \($i.finding)"]
      | if length == 0 then "None recorded." else join("\n") end' "$SUMMARY"
    printf '\n\n## Maintainer decision\n\n- [ ] Accept\n- [ ] Needs changes\n- [ ] Blocked on a documented human decision\n'
  } > "$file.tmp"
  mv "$file.tmp" "$file"
}

packet_for lib_core "Architecture and shared core" core
packet_for rule_syntax "Syntax rules" syntax-rules
packet_for rule_semantic "Semantic rules" semantic-rules
packet_for rule_pattern "Pattern rules" pattern-rules
packet_for tooling "Corpus, mutation, and maintainer tooling" tooling
packet_for ci "CI and operations" ci
packet_for docs "Documentation" documentation

{
  printf '# Merge review packets\n\n'
  printf 'Generated from the committed campaign manifest and finding summary at candidate `%s`.\n\n' "$(git -C "$REPO" rev-parse --short HEAD)"
  printf 'Review each packet’s evidence and record one maintainer decision. Regenerate after every completed campaign tranche.\n'
} > "$OUT/README.md.tmp"
mv "$OUT/README.md.tmp" "$OUT/README.md"
echo "wrote merge packets to $OUT"
