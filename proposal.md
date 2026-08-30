# Proposal: making the `evolution_accepted` review converge

## Executive summary

The existing review campaign is worth preserving, but it should not be restarted in its current form. The main problem is no longer Claude versus Codex; it is that the review/fix feedback loop produces far more work than it closes.

The recommended next step is to port the harness to a provider-neutral runner backed by Codex, strengthen its isolation and structured outputs, separate discovery from fixing, and validate the revised process with a small pilot before releasing the full 780-file queue.

## Current state

- The PR contains 563 commits and changes 710 files.
- Its diff has approximately 130,657 insertions and 10,663 deletions.
- The campaign manifest contains 780 files:
  - every file changed by the PR;
  - every current rule file, including rules untouched by the PR.
- The manifest does not currently include every untouched non-rule file in the repository.
- Review progress is 10/780 files.
- Nine of the ten reviewed files produced findings.
- Those reviews generated 42 fix entries:
  - 33 completed;
  - 9 parked after repeated reviewer/fixer disagreement;
  - 79 findings fixed;
  - 7 findings refuted;
  - 1 finding marked obsolete.
- Some files reached four or five review/fix rounds while overall progress remained at 1%.
- Both harness test suites currently pass:
  - `selftest.sh`: 78 assertions;
  - `selftest_manifest.sh`: 36 assertions.
- The worktree was clean at inspection time and `evolution_accepted` matched its remote.
- Codex CLI is installed and supports non-interactive execution.

## Assessment

The tooling has a strong foundation. In particular, the frozen manifest, resumability, integrity checks, independent CI gate, bounded memory, test gating, and append-only evidence are valuable and should be retained.

The principal concern is convergence:

```text
10 files reviewed
42 fix rounds created
9 files parked in reviewer/fixer disagreement
770 files still pending
```

The campaign currently optimizes for maximum scrutiny per file rather than reaching a reliable merge decision. Continuing unchanged could require hundreds or thousands of sessions and turn the audit into an indefinitely self-generating development project.

## Proposed approach

### 1. Freeze the candidate

Treat commit `11d8416d` as the initial review candidate. Do not add unrelated feature work while the audit is running.

Create a backup tag or remote branch before automated fixing begins. Automated attempts should not operate directly in the primary checkout.

### 2. Port the harness to Codex

Use `codex exec` for non-interactive sessions. The review invocation should be based on:

```bash
codex exec \
  --ephemeral \
  --sandbox read-only \
  --output-schema review-verdict.schema.json \
  --output-last-message "$VERDICT" \
  -C "$REPO" \
  "$prompt"
```

Required migration work:

- Replace `CLAUDE_MODEL` and `FIX_CLAUDE_MODEL` with provider-neutral settings such as `AGENT_MODEL` and `FIX_AGENT_MODEL`.
- Replace Claude's `--allowedTools` mechanism with Codex sandbox modes.
- Use `--sandbox read-only` for review sessions.
- Return review verdicts as structured final output instead of asking a read-only agent to write `_verdict`.
- Use `--sandbox workspace-write` for fix sessions.
- Prefer wrapper-owned commits: the fixer edits and reports, then the wrapper validates and commits an accepted diff.
- Run every fix attempt in a disposable Git worktree.
- Update self-test stubs to simulate `codex exec`, structured output, sandbox arguments, and model selection.

The runner should be provider-neutral even if Codex is initially its only implementation. This keeps session invocation details out of the review and fix orchestration.

### 3. Separate discovery from fixing

Do not alternate immediately between reviewing and repairing individual files.

Run a review-only tranche of approximately 25–40 rule files, then inspect the aggregate findings. This permits the campaign to:

- deduplicate shared-root-cause findings;
- measure the real blocker rate;
- identify recurring objections to intentional design decisions;
- improve prompts before spending full-suite gates and generating commits;
- fix a shared helper once instead of fixing symptoms across many rules.

Per-file isolation remains useful for independent judgment, but an aggregation stage is needed to recognize cross-file causes.

### 4. Tighten the severity policy

During the main pass:

- `blocker`: eligible for automated fixing;
- `concern`: collect for batch triage;
- `nit`: record but do not automatically fix;
- repeated disagreement: send to a human decision queue after one review and one fix response.

Initially run the equivalent of:

```bash
FIX_MIN_SEVERITY=blocker
```

Concerns and nits can be reconsidered after the blocker backlog is drained.

### 5. Review in risk order

Use the following order:

1. CI and baseline build reproducibility.
2. Shared core machinery:
   - `lib/credence.ex`;
   - corpus and analysis infrastructure;
   - source masking;
   - rule helpers;
   - syntax and semantic dispatch;
   - mutation machinery.
3. Newly added or substantially changed rules.
4. Unchanged rules affected by shared machinery.
5. Tests paired with rules that produced findings.
6. Remaining changed tests.
7. Tooling and documentation.
8. Unchanged non-rule files, only if literal whole-repository coverage is required.

This preserves review of untouched rules while examining changes capable of invalidating many downstream reviews first.

### 6. Add cross-cutting adversarial passes

Per-file review cannot reliably detect every system interaction. After each major category, run focused, read-only adversarial reviews for:

- rule ordering and diagnostic ownership;
- cross-rule interference;
- masking and byte-offset correctness;
- idempotency and repair convergence;
- compilation and execution containment;
- test-suite vacuity and fixture collisions;
- performance and memory regressions.

These passes should create findings rather than edits. Confirmed blockers should enter the normal fix queue.

### 7. Produce human-sized merge packets

The final deliverable should be a set of evidence-backed review packets rather than an expectation that a human reads the entire diff:

- architecture and shared-core changes;
- syntax rules;
- semantic rules;
- pattern rules;
- corpus and mutation tooling;
- CI and operational changes;
- documentation and generated artifacts;
- unresolved human decisions.

Each packet should state:

- what changed;
- risks considered;
- automated checks performed;
- blockers found and fixed;
- findings refuted;
- remaining uncertainty;
- relevant commits.

Splitting the branch into stacked PRs should be considered only after dependency analysis. Arbitrary splitting may create additional integration risk.

## Implementation sequence

1. Freeze and back up the candidate branch.
2. Introduce a provider-neutral agent runner with Codex as the first backend.
3. Add structured verdict and fix-report schemas.
4. Move sessions into disposable worktrees.
5. Make the wrapper responsible for accepted commits.
6. Change the campaign to review-first and blocker-only automatic fixing.
7. Add an aggregation and deduplication stage.
8. Run a 20-file Codex pilot.
9. Evaluate precision, runtime, cost, finding duplication, and convergence.
10. Adjust the process before releasing the remaining manifest.
11. Complete category reviews and adversarial passes.
12. Build the human-facing merge packets and decide whether the branch is ready to merge.

## Pilot success criteria

The 20-file pilot should not be expanded unless:

- review sessions reliably return schema-valid verdicts;
- read-only sessions cannot alter the checkout;
- failed fix attempts leave the primary checkout and branch history untouched;
- findings are sufficiently concrete to reproduce;
- shared-root-cause findings are deduplicated;
- reviewer/fixer disagreement does not loop indefinitely;
- the ratio of completed reviews to fix rounds is materially better than the current campaign;
- resource consumption stays within configured limits;
- a maintainer can understand progress and unresolved risks from the ledgers alone.

## Immediate next task

Implement the Codex runner and isolation changes, update the harness self-tests, and run the 20-file review-only pilot. Do not resume the entire campaign until the pilot has been evaluated.
