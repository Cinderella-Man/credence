# Confirmed unfixable / dropped — human-decided

Rules a human reviewed and decided to drop for good (no safe fix even on a narrow
core). Distil each reason into `CONTEXT.md` / the sister `prompt.md` so it is not
re-proposed.

## avoid_duplicate_enum_at — dropped 2026-06-16
- Files (sister `evolution`): `lib/pattern/avoid_duplicate_enum_at.ex` (+ check/fix/equivalence tests)
- Reason: re-attempt of the already-dropped `no_multiple_enum_at` family — it
  rewrites repeated `Enum.at(list, i)` into bindings/destructure, but `Enum.at`
  is **nil-safe past the end** while a destructure/index **crashes** on a short
  list (value→crash divergence). On top of that the synthetic `<i>_elem`
  bindings can **clobber existing in-scope variables**, and it emits
  **non-compiling code for inline `if`**. A safe version needs whole-scope
  variable analysis (a shared-helper concern), so there is no safe narrow core
  for a pattern rule. NO safe fix → dropped.
