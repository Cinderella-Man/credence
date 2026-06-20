# corpus_whitelist_validator

Autonomously re-audits the corpus over-firing whitelist
(`test/corpus/accepted_findings.txt`) in 100-finding batches, one read-only
Claude session per batch, looping with a configurable sleep between batches.

Each accepted finding is a suggestion the rule engine fired on idiomatic
production code. This tool re-checks them for **over-firing** (the rule fires
where its suggestion is wrong/silly) and **unsafe auto-fixes** (the fix would not
compile or would change behaviour) — the same audit done by hand in
`test/corpus/fix_breakage_test.exs`, but exhaustively across the whole whitelist.

## Files

- `prepare_batches.sh` — copies the whitelist into this dir and splits its
  findings into `data/batch_000.txt …` (100 rows each).
- `validate_loop.sh` — the orchestrator. One sandboxed (read-only, no-git)
  Claude session per batch; the session's final message is captured as
  `reports/<batch>.md`. Sleeps `wait_min` between batches.
- `validate_batch_prompt.md` — the read-only audit prompt the session runs.
- `showfix.exs` — helper the agent uses to see a rule's real fix diff on a
  corpus file (`mix run …/showfix.exs <rule> <path> <line>`).

## Usage

```bash
# stage batches + validate everything, 5 min between batches
maintainer_tools/corpus_whitelist_validator/validate_loop.sh

# validate at most 3 batches this run, 2 min between them
maintainer_tools/corpus_whitelist_validator/validate_loop.sh 3 2

# re-stage from a changed whitelist (clears data/ AND reports/)
ROWS_PER_BATCH=100 maintainer_tools/corpus_whitelist_validator/prepare_batches.sh
```

Args: `validate_loop.sh [cap] [wait_min]` — `cap` = max batches this run
(`0` = all remaining), `wait_min` = minutes between batches (default `5`).
Env: `CLAUDE_MODEL` sets `--model`; `ROWS_PER_BATCH` (prepare) sets batch size.

## Behaviour

- **First run** stages the batches (if `data/` is empty) and fetches the corpus
  once so the agent can read `corpus/<path>`.
- **Resumable**: a batch with a non-empty report is treated as done and skipped —
  stop with Ctrl-C and re-run to continue.
- **Transient failures** (agent crash / token limit / empty output) do not mark
  the batch done; the loop stays on it and retries with backoff.
- **Read-only**: the session has no Edit/Write/git tools — it only reads code and
  runs the read-only helpers, then prints a report. It never touches the
  whitelist or the rules; acting on flagged findings is a human decision.

## Output

`reports/batch_NNN.md` — per batch: the distinct rules, a `clean | N concern(s)`
verdict, and a FLAGGED list of `path:line — rule — severity — evidence` for any
finding whose fix is unsafe or over-firing. `.logs/batch_NNN.log` holds the full
agent transcript.

`data/`, `reports/`, `.logs/`, and the copied `accepted_findings.txt` are
generated artifacts (gitignored).
