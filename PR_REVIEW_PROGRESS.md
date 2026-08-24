# PR review implementation progress

This file is the durable progress ledger for implementing and running
[`proposal.md`](proposal.md). It is intentionally committed with the campaign
so work can resume after interruption. Remove it only in the final cleanup
commit after the review campaign is complete and the merge decision has been
recorded.

## Candidate

- Branch: `evolution_accepted`
- Initial reviewed candidate: `11d8416d9db885fc89ca8df9103907666b88fee6`
- Comparison branch: `main`

## Implementation checklist

- [x] Save the review proposal in the repository.
- [x] Add a provider-neutral agent runner with Codex as the default.
- [x] Capture verdicts and reports from agent final output.
- [x] Run Codex reviewers with an ephemeral read-only sandbox.
- [x] Run each fix attempt in a disposable Git worktree.
- [x] Make the wrapper, rather than the agent, own fix commits.
- [x] Run the independent gate in the disposable worktree before import.
- [x] Reduce Codex fix sessions to `workspace-write`.
- [x] Make the main campaign review-first and blocker-only by default.
- [x] Add finding aggregation and root-cause deduplication support.
- [x] Add cross-cutting adversarial review passes.
- [x] Add generation of human-sized merge packets.
- [x] Run one real Codex integration review.
- [x] Run and assess a 20-file Codex review-only pilot.
- [x] Run the initial seven cross-cutting adversarial review lanes.
- [ ] Complete the full category review campaign.
- [ ] Record the final merge decision and remaining uncertainties.
- [ ] Remove this progress ledger in the final cleanup commit.

## Verification log

- 2026-08-24: `selftest.sh` passed 81 assertions after Codex runner,
  wrapper-owned commits, pre-import gates, and disposable-worktree changes.
- 2026-08-24: `selftest_manifest.sh` passed 36 assertions.
- 2026-08-24: Bash syntax, ShellCheck, and `git diff --check` passed.
- 2026-08-24: Added committed finding summaries, adversarial review lanes,
  and category-based merge packets.
- 2026-08-24: All seven adversarial lanes completed without runner errors.
  They recorded 13 findings: seven blockers, four concerns, and two nits.
- 2026-08-24: After hardening dependency seeding and captured-report
  preservation, `selftest.sh` passed 81 assertions, `selftest_manifest.sh`
  passed 36 assertions, Bash syntax passed, and `git diff --check` passed.
  ShellCheck was unavailable on this host.

## Pilot results

- Integration review succeeded on
  `lib/syntax/fix_bare_tuple_zero_in_type.ex` using the Codex read-only
  sandbox. It returned one blocker and one concern, produced a valid captured
  verdict, changed no source files, and advanced the manifest from 10 to 11
  reviewed files.
- The complete pilot ran 20 Codex sessions with zero invalid outputs, retries,
  sandbox violations, or source-tree writes. Nineteen files returned findings
  and one returned `OK`; the tranche added 24 blockers, 5 concerns, and 1 nit.
- The high blocker rate means the remaining 750 review rows have not been
  released automatically. Fourteen blocker-bearing fix rounds were queued and
  five below-floor rounds were recorded as skipped.
- The first real wrapper-owned fix completed in a disposable worktree. Its
  full gate passed before commit `0851b12a` was imported, and the manifest was
  refreshed afterward.
- Deployment issue: user-level `systemd-run` is unavailable on this host, so
  bulk fix sessions remain paused until an equivalent memory cap is available
  or explicitly accepted. The worktree gate is non-interactive and uses a
  private dependency copy.
- The adversarial lanes found blockers in diagnostic ownership, cross-rule
  line stability, nested sigil masking, and execution containment. These are
  now recorded in `maintainer_tools/pr_review/adversarial_findings.md` and must
  be triaged before the remaining review queue is released.

## Human decisions

The historical campaign currently has nine parked fix entries caused by
review/fix disagreement. Reassess these after the new aggregation pass rather
than automatically requeueing them.
