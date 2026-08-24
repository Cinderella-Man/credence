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
- [ ] Make the wrapper, rather than the agent, own fix commits.
- [ ] Run the independent gate in the disposable worktree before import.
- [ ] Reduce Codex fix sessions to `workspace-write`.
- [ ] Make the main campaign review-first and blocker-only by default.
- [ ] Add finding aggregation and root-cause deduplication support.
- [ ] Add cross-cutting adversarial review passes.
- [ ] Add generation of human-sized merge packets.
- [ ] Run one real Codex integration review.
- [ ] Run and assess a 20-file Codex review-only pilot.
- [ ] Complete the full category review campaign.
- [ ] Record the final merge decision and remaining uncertainties.
- [ ] Remove this progress ledger in the final cleanup commit.

## Verification log

- 2026-08-24: `selftest.sh` passed 80 assertions after Codex runner and
  disposable-worktree implementation.
- 2026-08-24: `selftest_manifest.sh` passed 36 assertions.
- 2026-08-24: Bash syntax, ShellCheck, and `git diff --check` passed.

## Pilot results

Not started.

## Human decisions

The historical campaign currently has nine parked fix entries caused by
review/fix disagreement. Reassess these after the new aggregation pass rather
than automatically requeueing them.
