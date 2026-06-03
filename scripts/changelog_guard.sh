#!/usr/bin/env bash
#
# changelog_guard.sh — fail the build if the safety-switch defaults changed
# without a matching CHANGELOG entry (decision 16 of docs/03-safety-switches.md).
#
# The helpful default can change what Credence does between versions: the day a
# default-on switch is added or flipped, an app that upgrades could see its code
# rewritten in a new way. That is a behaviour change tied to a version, so it
# must be written down where upgraders look. This is the lightest enforcement
# that works — like the property-test meta-test (decision 18), it can't judge
# whether the CHANGELOG *line* is good, but it turns "shipped a default-on
# behaviour change with no changelog" into a red build.
#
# It flags a change when the diff to lib/assumptions.ex touches a registry
# `default:` line while CHANGELOG.md is untouched in the same range.
#
# Base ref defaults to origin/main; override with arg 1 or BASE=<ref>. Falls
# back to main, then HEAD~1, then an empty tree (first commit).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"
cd "$REPO"

BASE="${1:-${BASE:-origin/main}}"
if ! git rev-parse --verify --quiet "$BASE" >/dev/null; then
  if git rev-parse --verify --quiet main >/dev/null; then
    BASE="main"
  elif git rev-parse --verify --quiet HEAD~1 >/dev/null; then
    BASE="HEAD~1"
  else
    # First commit — diff against the empty tree.
    BASE="$(git hash-object -t tree /dev/null)"
  fi
fi

# Did the registry defaults change? (added/removed lines containing `default:`
# in the assumptions module.)
defaults_changed=0
if git diff --unified=0 "$BASE"...HEAD -- lib/assumptions.ex \
   | grep -E '^[+-][[:space:]]*default:' >/dev/null 2>&1; then
  defaults_changed=1
fi

if [[ "$defaults_changed" -eq 0 ]]; then
  echo "changelog guard: assumptions defaults unchanged since $BASE — OK"
  exit 0
fi

if git diff --quiet "$BASE"...HEAD -- CHANGELOG.md; then
  echo "ERROR: lib/assumptions.ex registry defaults changed since $BASE, but" >&2
  echo "       CHANGELOG.md was not updated. A default-on switch change is a" >&2
  echo "       behaviour change on upgrade — add a CHANGELOG entry." >&2
  exit 1
fi

echo "changelog guard: defaults changed and CHANGELOG.md updated — OK"
