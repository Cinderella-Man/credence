#!/usr/bin/env bash
# Provider-neutral session adapter.
# Usage: printf '%s' "$prompt" | agent_runner.sh review|fix OUTPUT_FILE
set -uo pipefail

MODE="${1:-}"
OUTPUT="${2:-}"
PROVIDER="${AGENT_PROVIDER:-codex}"

die() { printf '[agent_runner] FATAL: %s\n' "$*" >&2; exit 64; }
case "$MODE" in review|fix) ;; *) die "mode must be review or fix" ;; esac
[[ -n "$OUTPUT" ]] || die "output file is required"
PROMPT="$(cat)"
[[ -n "$PROMPT" ]] || die "prompt on stdin is empty"

DEFAULT_MODEL="${AGENT_MODEL:-${CLAUDE_MODEL:-}}"
case "$MODE" in
  review) MODEL="${REVIEW_AGENT_MODEL:-$DEFAULT_MODEL}" ;;
  fix) MODEL="${FIX_AGENT_MODEL:-${FIX_CLAUDE_MODEL:-$DEFAULT_MODEL}}" ;;
esac
rm -f -- "$OUTPUT"

case "$PROVIDER" in
  codex)
    BIN="${AGENT_BIN:-codex}"
    command -v "$BIN" >/dev/null || die "Codex executable not found: $BIN"
    sandbox=read-only
    # Fix sessions still author commits, so they need .git access. This can
    # become workspace-write once commit ownership moves to the wrapper.
    [[ "$MODE" == fix ]] && sandbox=danger-full-access
    args=(exec --ephemeral --color never --sandbox "$sandbox" -C "${AGENT_REPO:?}" -o "$OUTPUT")
    [[ -n "$MODEL" ]] && args+=(--model "$MODEL")
    printf '%s' "$PROMPT" | "$BIN" "${args[@]}" -
    ;;
  claude)
    BIN="${AGENT_BIN:-claude}"
    command -v "$BIN" >/dev/null || die "Claude executable not found: $BIN"
    tools="Read Grep Glob"
    [[ "$MODE" == fix ]] && tools="Read Grep Glob Write Edit Bash"
    args=(-p "$PROMPT" --allowedTools "$tools")
    [[ -n "$MODEL" ]] && args+=(--model "$MODEL")
    "$BIN" "${args[@]}" | tee "$OUTPUT"
    ;;
  *) die "unknown AGENT_PROVIDER '$PROVIDER' (supported: codex, claude)" ;;
esac

[[ -s "$OUTPUT" ]] || die "provider returned no final output"
