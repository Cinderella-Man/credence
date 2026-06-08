# Stage 3 — confirmed unfixable

Rejected followup rules that stage 3 re-examined and proved genuinely terminal: a
value-type change (e.g. charlist→integers), or a side-effect / double-eval /
sort-stability divergence that cannot be framed as a checkable data promise. No
safe core, no switch helps. Terminal record — never re-read as input.

<!-- entries appended below by resurrect_loop.sh -->
## no_case_digit_to_integer — 2026-06-06
- Files:
  - `lib/pattern/no_case_digit_to_integer.ex`
  - `test/pattern/no_case_digit_to_integer_test.exs`
- Reason: partial digit case (CaseClauseError off "0".."9") vs near-total String.to_integer — diverges raise-vs-return on "10"/"00"/"07"/"-1"/"+5" and CaseClauseError-vs-ArgumentError on non-digits; agree only on the exact single-char "0".."9", no general data promise covers that micro-domain

