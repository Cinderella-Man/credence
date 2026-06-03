# Follow-up list

Items pulled out of the candidate queue that need dedicated human attention
(not handled by the per-rule review loop). Reviewed case by case.

## Global / end-to-end test suites — 2026-06-03
- Files:
  - `test/credence_test.exs`
  - `test/debug_ast_test.exs`
  - `test/fix_examples_test.exs`
  - `test/fix_showcase_test.exs`
- Reason: these are whole-system suites, not tied to a single rule. Their
  `evolution` versions assert the behaviour of rules that have not been accepted
  yet, so they can't be reviewed in isolation.
- Suggested action: review **last**, once the rule set has settled, and reconcile
  each assertion against the rules that actually landed.

## `lib/syntax.ex` — runner behaviour change — **REJECTED** (rules were misfiled) — 2026-06-03
- File: `lib/syntax.ex`
- Decision: **do not bring the `evolution` runner change over. Keep `lib/syntax.ex`
  as-is** (accepted branch). The `apply_rules_traced/2` extraction is a clean DRY
  refactor, but the behaviour change it enables — run syntax rules even when the
  source already parses — is a workaround for two rules that were filed in the wrong
  phase, and it ships real defects.
- Why the change is wrong, not just incomplete:
  1. **Masking regression (confirmed empirically).** The top-level `Credence.analyze/2`
     gate is `if Enum.any?(syntax_issues) -> %{valid: false, issues: syntax_issues}`
     (stops; never runs semantic/pattern). It assumes "syntax issue ⇒ won't parse."
     Once syntax rules fire on parseable code, a single misplaced `@moduledoc`
     suppresses **every** semantic + pattern issue in the file. Demonstrated: identical
     code with `length(x) == 0` reported only `:module_attr_outside_module` with the
     attr misplaced, but `:no_length_comparison_for_empty` once placed correctly.
     `evolution` did **not** change `lib/credence.ex`, so this regression is live.
  2. Stale docs (moduledoc + `fix_with_trace/2` @doc now contradict behaviour) and no
     parse-verify on the now-active `{:ok}` branch (valid code can be turned invalid
     silently, with no downstream revert).
- Root cause: the two rules that *needed* this change target **parseable** code, so by
  the phase taxonomy (syntax = won't parse; semantic = compiler diagnostic; pattern =
  AST-detectable) they are **not syntax rules**. Both `@moduledoc`-before-`defmodule`
  and a literal-list typespec parse fine and raise on compile with **0 captured
  diagnostics** (so semantic, which is diagnostic-driven, can't host them either) — but
  they are cleanly **AST-detectable**, i.e. **pattern** rules.
- Action: **reclassify** `fix_module_attr_outside_module` and `fix_typespec_literal_list`
  from syntax → **pattern** (rewrite detection from string-scanning to AST-walking;
  pattern's `apply_or_revert` compiles the *result*, so a non-compiling input with a
  compilable fix is fine). Then `lib/syntax.ex` needs **no change**, the masking bug
  never arises, and the 4 genuinely-unparseable fixers stay as syntax rules.
- **DONE (2026-06-03):** both reclassified + reimplemented as AST-based pattern rules,
  each narrowed to its safe core and shipped with split check/fix tests:
  - `lib/pattern/no_literal_list_typespec.ex` — `[t, t]`→`{t, t}` in `@spec` returns;
    narrowed to all-type-call elements (skips keyword lists, `[t, ...]`, `[:ok, :error]`,
    single-element lists).
  - `lib/pattern/no_attr_before_defmodule.ex` — moves `@moduledoc/@doc/@spec/@type` that
    precede a `defmodule` into it; **dropped** the destructive de-dup and the
    `defmodule Solution` wrap (intent-guessing); existing-module-only.
  `lib/syntax.ex` left byte-identical; the evolution runner change remains rejected.
  Full suite green (3213 tests). The old syntax entries are removed from `pr_diff.md`.
