# Stage 3 — confirmed unfixable

Rejected followup rules that stage 3 re-examined and proved genuinely terminal: a
value-type change (e.g. charlist→integers), or a side-effect / double-eval /
sort-stability divergence that cannot be framed as a checkable data promise. No
safe core, no switch helps. Terminal record — never re-read as input.

<!-- entries appended below by resurrect_loop.sh -->
