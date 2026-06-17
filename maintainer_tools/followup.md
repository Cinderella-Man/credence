# Followup — rules needing human attention

Stage 1 (`stage_1_promote_fixable_rules/review_loop.sh`) appends one section per
set it could not safely promote: no safe fix, duplicate, needs a shared-file
change, type change, or inconclusive. Each entry lists the set's files and the
one-line reason. Work these by hand later.

## test/pattern/assumptions_filtering_test.exs — 2026-06-17
- Reason: orphan test — no owning rule in tree or sister.
