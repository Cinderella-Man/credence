# Corpus, mutation, and maintainer tooling

Candidate: `0851b12a` against `main`.

## Files

- `maintainer_tools/199-no_negative_step_in_string_slice.patch` — pending, verdict: not reviewed
- `maintainer_tools/candidates.md` — pending, verdict: not reviewed
- `maintainer_tools/corpus_whitelist_validator/FIX_LOG.md` — pending, verdict: not reviewed
- `maintainer_tools/corpus_whitelist_validator/accepted_findings.txt` — pending, verdict: not reviewed
- `maintainer_tools/escalation_ledger.md` — pending, verdict: not reviewed
- `maintainer_tools/followup.md` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/README.md` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/adversarial_review.sh` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/agent_runner.sh` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/aggregate_findings.sh` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/campaign.sh` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/finding_summary.json` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/finding_summary.md` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/fix_file_prompt.md` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/fix_loop.sh` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/fix_queue.sh` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/generate_manifest.sh` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/generate_merge_packets.sh` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/merge_packets/README.md` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/merge_packets/ci.md` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/merge_packets/core.md` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/merge_packets/documentation.md` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/merge_packets/pattern-rules.md` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/merge_packets/semantic-rules.md` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/merge_packets/syntax-rules.md` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/merge_packets/tooling.md` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/requeue.sh` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/review_file_prompt.md` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/review_loop.sh` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/run_capped.sh` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/selftest.sh` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/selftest_manifest.sh` — pending, verdict: not reviewed
- `maintainer_tools/pr_review/status.sh` — pending, verdict: not reviewed
- `maintainer_tools/proposed_assumptions.md` — pending, verdict: not reviewed
- `maintainer_tools/proposed_rules_requiring_assumptions.md` — pending, verdict: not reviewed
- `maintainer_tools/shared_deltas.md` — pending, verdict: not reviewed
- `maintainer_tools/stage3_unfixable.md` — pending, verdict: not reviewed
- `maintainer_tools/stage_1_promote_fixable_rules/README.md` — pending, verdict: not reviewed
- `maintainer_tools/stage_1_promote_fixable_rules/review_loop.sh` — pending, verdict: not reviewed
- `maintainer_tools/stage_1_promote_fixable_rules/review_set_prompt.md` — pending, verdict: not reviewed
- `maintainer_tools/unfixable_confirmed.md` — pending, verdict: not reviewed
- `maintainer_tools/unfixable_unreviewed.md` — pending, verdict: not reviewed

## Active findings

- **concern** `maintainer_tools/pr_review/run_capped.sh` — maintainer_tools/pr_review/run_capped.sh:24 — when user systemd scopes are unavailable, the advertised safety wrapper deliberately executes the command uncapped; any documented `mix run` fixture reproduction on a container, CI shell, or host without a user systemd session regains the machine-level OOM failure this wrapper claims to prevent.


## Maintainer decision

- [ ] Accept
- [ ] Needs changes
- [ ] Blocked on a documented human decision
