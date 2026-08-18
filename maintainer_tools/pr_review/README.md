# PR review — the whole `evolution_accepted` diff, one file at a time

Reviews the entire PR (`main`...`evolution_accepted`, 500+ commits, ~690 files)
**plus every rule file the PR never touched**, one file per fresh, sandboxed,
read-only Claude session. Progress lives in `manifest.json` — a flat tick-off
list — so the campaign is resumable at any point and "how far along is it?" is
one `./status.sh` away.

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
  produced findings. `OK` files get no section (the JSON records them).
- `review_file_prompt.md` — the session protocol (the bar, the lenses, the
  verdict format).
- `_verdict`, `_briefing/`, `.review_logs/`, `.lock` — transient, gitignored.
  `.review_logs/<path>.log` holds the full per-file session transcript.

## Sandbox model

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

## Run

```
./generate_manifest.sh              # once; refuses to overwrite
./generate_manifest.sh --dry-run    # preview the file list + counts
./review_loop.sh                    # run until manifest drained
./review_loop.sh 1                  # exactly one file, then exit
./review_loop.sh 20 1               # 20 files, 1 min between sessions
./status.sh                         # progress digest
./requeue.sh --errors               # error rows → pending
./requeue.sh <path>...              # specific rows → pending (re-review;
                                    #   resets verdict/findings in the JSON —
                                    #   old findings.md sections stay, it is
                                    #   an append-only log)
```

Env: `CLAUDE_MODEL` (optional `--model` for sessions), `MAX_RETRIES` (3),
`COMMIT_EVERY` (0 = the loop never touches git; N = auto-commit
`manifest.json` + `findings.md` every N reviewed files),
`BASE_BRANCH`/`HEAD_BRANCH` for the generator (default `main` /
`evolution_accepted`).

Run **one loop instance at a time** (enforced with a lock file). Sessions are
serial by design — this is a marathon, not a fan-out.

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
`stale: true`; new files enter as `pending`.
