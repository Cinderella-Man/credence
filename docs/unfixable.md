# Unfixable list

Rules auto-filtered out of the candidate queue by `scripts/move_unfixable_out.sh`
because they are **provably check-only** — they detect a problem but ship no real
fix, so by project policy (Credence has no warn-only mode) they cannot be accepted.

Detection is the strict, light static `unfixable_stub?` predicate (per kind):
- **pattern** — `fix_patches/2` is a single constant `[]` clause.
- **semantic** — every `fix/2` clause returns `source` verbatim.
- **syntax** — every `fix/1` clause returns `source` verbatim.

Anything subtler is left in the queue for the review loop's agent to judge.
Each entry below records the rule path, its test file(s), the reason, and the date.
