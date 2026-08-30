# PR review — the whole `evolution_accepted` diff, one file at a time

Reviews **and fixes** the entire PR (`main`...`evolution_accepted`, 500+
commits, ~690 files) **plus every rule file the PR never touched**, one file
per fresh agent session. Codex is the default provider; a Claude adapter is
retained for compatibility. Progress lives in `manifest.json` (review
tick-off list) and `fixes.json` (fix ledger), so the campaign is resumable at
any point and "how far along is it?" is one `./status.sh` away.

Two session kinds with opposite trust models:

- **Review sessions** are read-only (no Bash, no Edit) and produce a verdict.
- **Fix sessions** are developers: for every finding they must reproduce the
  defect with something they *executed*, pin it with a test that fails on the
  current code, fix it minimally, prove the rule's own tests green, and commit
  — the wrapper runs the full suite itself, so the session does not — or
  honestly refute/defer with evidence. The wrapper trusts none of it: it
  re-runs the gate itself and a red gate discards every commit of the attempt.

`./campaign.sh` alternates the two so findings get fixed as they are found;
after a fix lands, the manifest refreshes and the fixed file re-enters review
as stale — the next review session verifies the fixer's work.

## Why unchanged rules are in scope

The PR changes shared code *underneath* every rule (helpers, Semantic dispatch,
masking, ordering). A rule that was correct on `main` can be wrong on this
branch without its own file changing. So the universe is:

- every file changed between `merge-base(main, evolution_accepted)` and the
  branch tip (added / modified / renamed / deleted), **and**
- every current `lib/{syntax,semantic,pattern}/*.ex` rule file, even if
  untouched (`origin: unchanged_rule` — reviewed from scratch).

## Why a rule's tests wait for the rule

A test file whose rule the campaign has not reviewed yet enters as `gated`, not
`pending`, carrying `gated_by: <its rule>`. The rule's own review opens them —
but only if it came back with findings. A rule that reviews clean leaves its
tests gated.

The measurement behind it, from the 2026-08-19 run: 21 reviews of `lib/` rule
files produced **14 blockers**; 22 reviews of `test/` files produced **none** (8
concerns, 33 nits). Test files are 392 of the 780 rows — half the universe.

This is a scheduling bet, not a claim that test files are clean: a vacuous test
masks another defect, which is the blocker definition. It bets that the rule's
own review is the cheaper place to notice. `./requeue.sh --gated` opens the
whole set when the rule pass is done, and `status.sh` never stops reporting the
count.

## Data files (in this directory)

- `manifest.json` — **committed**. The tick-off list. Base/head SHAs are frozen
  in at generation, so committing review progress (which moves the branch tip)
  does not change the universe. One entry per file:
  `path, origin, category, insertions, deletions, blob, old_path, gated_by,
  status (pending|gated|done|error), verdict (OK|FINDINGS), findings (count),
  reviewed_at, stale, rereviews, error`.
- `findings.md` — **committed**. Append-only; one `##` section per file that
  produced findings, plus one `## <path> — fix round N` section per fix
  session recording what happened to each finding. `OK` files get no section
  (the JSON records them).
- `fixes.json` — **committed**. The fix ledger: one entry per review that
  produced findings, keyed `(path, reviewed_at)` with a per-path `round`
  counter. DERIVED from manifest+findings.md (`fix_queue.sh sync` backfills),
  so it can be rebuilt at any time. Per entry: `status
  (pending|done|skipped|error), outcomes ([{n, severity, outcome
  (fixed|refuted|obsolete|deferred), note}]), commits, gate, needs_human,
  attempts, error`.
- `agent_runner.sh` — provider-neutral session adapter (`codex` or `claude`).
- `aggregate_findings.sh` — builds committed JSON/Markdown blocker and
  repeated-root-cause summaries after each review tranche.
- `adversarial_review.sh` — seven cross-cutting read-only review lenses.
- `generate_merge_packets.sh` — category-based human review packets.
- `review_file_prompt.md` / `fix_file_prompt.md` — the two session protocols.
- `_verdict`, `_fix_report`, `_briefing/`, `.review_logs/`, `.fix_logs/`,
  `.fix_scratch/`, `.lock`, `.campaign.lock` — transient, gitignored.
  `.review_logs/<path>.<timestamp>.log` and `.fix_logs/<path>.roundN.log` hold the full
  per-session transcripts; `.fix_logs/<path>.roundN.gate.log` the wrapper's
  own gate run.

## Sandbox model (review sessions)

The Codex adapter runs review sessions with `--sandbox read-only` and
`--ephemeral`. The prompt also tells the reviewer not to compile or run
anything (see docs/21: the OOMs came from ad-hoc compiles; read-only reviewers
*name* the experiment, the maintainer runs it).

The legacy Claude adapter still relies on its allowed-tools request and the
tree guard rather than an OS sandbox. The Codex path is therefore the preferred
one. The existing porcelain and ledger guards remain as defense in depth.

The runner captures the agent's final response in `_verdict`:

```
OK
```
or
```
FINDINGS
- blocker: <path>:<line> — <one sentence>
- concern: ...
- nit: ...
- experiment: <one command that settles a named uncertainty>
```

The wrapper defends itself in layers: `manifest.json` and `findings.md` are
backed up and hash-checked around every session (porcelain can't see writes
into already-dirty files, and these two are dirty all campaign) and restored if
touched; `git status` is snapshotted around every session and new dirt is
reverted (untracked dirs removed, tracked files restored from the index so
staged work survives); if the revert cannot restore the pre-session state the
loop aborts loudly. Files already dirty *before* the loop starts are a blind
spot — it warns about them at startup; ideally run on a clean tree.

Before every row the worktree file is hash-checked against the manifest's
frozen blob (and the loop refuses to start unless the frozen head is an
ancestor of the current checkout), so a branch switch or local edit turns into
a visible `error` row instead of a verdict about content nobody reviewed.

A row with no usable verdict retries with backoff (2/4/6… min, max 10) up to
`MAX_RETRIES` (default 3), then is marked `error` and the loop moves on — one
stuck file never blocks the other 700.

## Trust model (fix sessions)

A fix session must compile, run tests, and edit files. The wrapper
creates a fresh temporary Git branch and linked worktree for every attempt;
the agent never runs in the maintainer's checkout and uses Codex's
`workspace-write` sandbox. The agent is forbidden to commit. The wrapper
validates its report and changed paths, creates one commit, runs the gate in
the disposable worktree, and only then cherry-picks the green commit into the
campaign branch:

1. restores `manifest.json`/`findings.md`/`fixes.json` if the session touched
   them, and discards commits that touch `maintainer_tools/pr_review/`;
2. refuses branch switches and history rewrites (pre-session commit must
   remain an ancestor);
3. reverts uncommitted leftovers — tracked-file dirt voids the attempt;
4. requires the report (`_fix_report`) to account for every finding exactly
   once, with `fixed` claims backed by commits;
5. **runs the CI fast gate itself before import** — `mix format` on touched files,
   `mix compile --warnings-as-errors`, `mix test --exclude corpus --exclude
   idempotency`, and the tree must stay clean (fixture-healer parity with CI).
   Red gate ⇒ the disposable branch is deleted and the session retries with
   the gate output as feedback; the campaign branch is never touched.

The temporary worktree and branch are force-removed after every attempt,
whether the session succeeds, fails, times out, or leaves uncommitted files.

Sessions and the gate run under a systemd `MemoryMax` scope (default 16G,
`FIX_MEM_MAX` to change, empty to disable) — the OOM history here is unbounded
compiles, and fix sessions compile. Ad-hoc emissions inside a session go
through `run_capped.sh` (4G default).

An accepted entry records per-finding outcomes: `fixed` (confirmed + pinned +
committed), `refuted` (reproduction attempted, code is right — with evidence),
`obsolete` (an earlier commit already addressed it), `deferred` (a policy
question only a human can settle; surfaced by `status.sh` as needs-human).
After accepted commits the manifest refreshes: fixed files re-enter review as
`stale` — the reviewer verifies the fixer — but only `MAX_REREVIEWS` times
(default 1). Past that the row keeps its verdict and carries `stale: true`:
visible in `status.sh`, not in the queue, swept at the end with
`./requeue.sh --stale`. The uncapped version is what never converged — a
re-review is a *fresh* full review, a freshly rewritten file reliably yields
something, and in the 2026-08-19 run every file circled until it parked at the
fix round cap.
A round carrying nothing at or above `FIX_MIN_SEVERITY` (default `concern`) is
recorded as `skipped` rather than scheduled: a pile of nits is not worth a fix
session plus a full-suite gate each, and scheduling one also re-stales the file
and buys another review. Sweep them at the end with
`FIX_MIN_SEVERITY=nit ./fix_queue.sh requeue --skipped`.

A file can go around the review↔fix loop at most `FIX_MAX_ROUNDS` (3) times
before it parks as needs-human.

## Run

```
./generate_manifest.sh              # once; refuses to overwrite
./generate_manifest.sh --dry-run    # preview the file list + counts

./campaign.sh                       # review all pending, aggregate, fix blockers
./campaign.sh 20 1                  # 20-review tranche, aggregate, fix blockers

./review_loop.sh [cap] [wait_min]   # review only
./fix_loop.sh [cap] [wait_min]      # fix only (drains the findings backlog)

./status.sh                         # progress digest (review + fixes)
./requeue.sh --errors               # review error rows → pending
./requeue.sh --stale                # rows that settled at the re-review cap
./requeue.sh --gated                # test rows whose rule reviewed clean
./requeue.sh <path>...              # re-review specific rows
./fix_queue.sh sync                 # backfill fixes.json from findings.md
./fix_queue.sh requeue --errors     # fix error entries → pending
FIX_MIN_SEVERITY=nit ./fix_queue.sh requeue --skipped   # the end-of-campaign nit sweep
./fix_queue.sh requeue <path>...    # retry the latest fix entry for a path
./selftest.sh                       # prove the fix-pipeline mechanics
./selftest_manifest.sh              # prove the review-side scheduling
./aggregate_findings.sh             # refresh finding_summary.{md,json}
./adversarial_review.sh all         # seven cross-cutting read-only passes
./generate_merge_packets.sh         # refresh merge_packets/
```

Env: `AGENT_PROVIDER` (`codex` by default, or `claude`), `AGENT_BIN` (optional
executable override), `AGENT_MODEL` (optional model for all sessions),
`REVIEW_AGENT_MODEL` / `FIX_AGENT_MODEL` (per-mode overrides), `MAX_RETRIES`
(3 review / 2 fix),
`COMMIT_EVERY` (0 = the loop never touches git; N = auto-commit the three
ledgers every N reviewed files), `BASE_BRANCH`/`HEAD_BRANCH` and `MAX_REREVIEWS` for the
generator (default `main` / `evolution_accepted` / `1`), and the fix knobs
documented in `fix_loop.sh`'s header (`FIX_MEM_MAX`, `FIX_SESSION_TIMEOUT`,
`FIX_GATE_TIMEOUT`, `FIX_MAX_ROUNDS`, `FIX_MIN_SEVERITY`, `FIX_REFRESH`).

Run **one loop instance at a time** (enforced with a lock file; the campaign
holds its own second lock). Sessions are serial by design — this is a
marathon, not a fan-out. Fix commits land on the current branch as ordinary
commits (`pr_review fix: <path> — …`), one per finding, revertable one by one.

## Review order

Syntax rules → their tests → Semantic rules → their tests → Pattern rules →
their tests → `lib/` core → other tests → tooling → CI → docs → the rest.
Within each rule kind, entries sort by rule base name with the rule file
immediately before its own tests, so consecutive sessions build on adjacent
context (each session is still independent).

## Refresh (the branch moved)

`./generate_manifest.sh --refresh` recomputes the universe against the current
tips and merges: entries whose blob is unchanged keep their status/verdict;
reviewed entries whose content changed since review go back to `pending` with
`stale: true`; new files enter as `pending`. `fix_loop.sh` runs this
automatically after accepted commits, which is how fixed files re-enter
review and freshly-written test files enter the universe at all.
