# PR review — the whole `evolution_accepted` diff, one file at a time

Reviews **and fixes** the entire PR (`main`...`evolution_accepted`, 500+
commits, ~690 files) **plus every rule file the PR never touched**, one file
per fresh, sandboxed Claude session. Progress lives in `manifest.json` (review
tick-off list) and `fixes.json` (fix ledger), so the campaign is resumable at
any point and "how far along is it?" is one `./status.sh` away.

Two session kinds with opposite trust models:

- **Review sessions** are read-only (no Bash, no Edit) and produce a verdict.
- **Fix sessions** are developers: for every finding they must reproduce the
  defect with something they *executed*, pin it with a test that fails on the
  current code, fix it minimally, prove the fast gate green, and commit — or
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

## Data files (in this directory)

- `manifest.json` — **committed**. The tick-off list. Base/head SHAs are frozen
  in at generation, so committing review progress (which moves the branch tip)
  does not change the universe. One entry per file:
  `path, origin, category, insertions, deletions, blob, old_path, status
  (pending|done|error), verdict (OK|FINDINGS), findings (count), reviewed_at,
  stale, error`.
- `findings.md` — **committed**. Append-only; one `##` section per file that
  produced findings, plus one `## <path> — fix round N` section per fix
  session recording what happened to each finding. `OK` files get no section
  (the JSON records them).
- `fixes.json` — **committed**. The fix ledger: one entry per review that
  produced findings, keyed `(path, reviewed_at)` with a per-path `round`
  counter. DERIVED from manifest+findings.md (`fix_queue.sh sync` backfills),
  so it can be rebuilt at any time. Per entry: `status
  (pending|done|error), outcomes ([{n, severity, outcome
  (fixed|refuted|obsolete|deferred), note}]), commits, gate, needs_human,
  attempts, error`.
- `review_file_prompt.md` / `fix_file_prompt.md` — the two session protocols.
- `_verdict`, `_fix_report`, `_briefing/`, `.review_logs/`, `.fix_logs/`,
  `.fix_scratch/`, `.lock`, `.campaign.lock` — transient, gitignored.
  `.review_logs/<path>.log` and `.fix_logs/<path>.roundN.log` hold the full
  per-session transcripts; `.fix_logs/<path>.roundN.gate.log` the wrapper's
  own gate run.

## Sandbox model (review sessions)

The session gets `Read Grep Glob Write` — **no Bash, no Edit**. It cannot
compile or run anything (see docs/21: the OOMs came from ad-hoc compiles;
read-only reviewers *name* the experiment, the maintainer runs it). Its only
output channel is `_verdict`:

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

A fix session gets `Read Grep Glob Write Edit Bash` — it must compile, run
tests, and commit, so it cannot be sandboxed the way reviewers are. Instead
the wrapper (`fix_loop.sh`) is the trust boundary; after every session it:

1. restores `manifest.json`/`findings.md`/`fixes.json` if the session touched
   them, and discards commits that touch `maintainer_tools/pr_review/`;
2. refuses branch switches and history rewrites (pre-session commit must
   remain an ancestor);
3. reverts uncommitted leftovers — tracked-file dirt voids the attempt;
4. requires the report (`_fix_report`) to account for every finding exactly
   once, with `fixed` claims backed by commits;
5. **re-runs the CI fast gate itself** — `mix format` on touched files,
   `mix compile --warnings-as-errors`, `mix test --exclude corpus --exclude
   idempotency`, and the tree must stay clean (fixture-healer parity with CI).
   Red gate ⇒ `git reset --hard` to the pre-session commit (campaign ledgers
   preserved) and the session retries with the gate output as feedback.

Sessions and the gate run under a systemd `MemoryMax` scope (default 16G,
`FIX_MEM_MAX` to change, empty to disable) — the OOM history here is unbounded
compiles, and fix sessions compile. Ad-hoc emissions inside a session go
through `run_capped.sh` (4G default).

An accepted entry records per-finding outcomes: `fixed` (confirmed + pinned +
committed), `refuted` (reproduction attempted, code is right — with evidence),
`obsolete` (an earlier commit already addressed it), `deferred` (a policy
question only a human can settle; surfaced by `status.sh` as needs-human).
After accepted commits the manifest refreshes: fixed files re-enter review as
`stale`, new test files enter as `pending` — the reviewer verifies the fixer.
A file can go around the review↔fix loop at most `FIX_MAX_ROUNDS` (3) times
before it parks as needs-human.

## Run

```
./generate_manifest.sh              # once; refuses to overwrite
./generate_manifest.sh --dry-run    # preview the file list + counts

./campaign.sh                       # review AND fix until both drained
./campaign.sh 20 1                  # cap 20 review sessions, 1 min between

./review_loop.sh [cap] [wait_min]   # review only
./fix_loop.sh [cap] [wait_min]      # fix only (drains the findings backlog)

./status.sh                         # progress digest (review + fixes)
./requeue.sh --errors               # review error rows → pending
./requeue.sh <path>...              # re-review specific rows
./fix_queue.sh sync                 # backfill fixes.json from findings.md
./fix_queue.sh requeue --errors     # fix error entries → pending
./fix_queue.sh requeue <path>...    # retry the latest fix entry for a path
./selftest.sh                       # prove the fix-pipeline mechanics
```

Env: `CLAUDE_MODEL` (optional `--model` for sessions; `FIX_CLAUDE_MODEL`
overrides it for fix sessions), `MAX_RETRIES` (3 review / 2 fix),
`COMMIT_EVERY` (0 = the loop never touches git; N = auto-commit the three
ledgers every N reviewed files), `BASE_BRANCH`/`HEAD_BRANCH` for the
generator (default `main` / `evolution_accepted`), and the fix knobs
documented in `fix_loop.sh`'s header (`FIX_MEM_MAX`, `FIX_SESSION_TIMEOUT`,
`FIX_GATE_TIMEOUT`, `FIX_MAX_ROUNDS`, `FIX_REFRESH`).

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
