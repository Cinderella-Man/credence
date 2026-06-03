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

## `lib/syntax.ex` — runner behaviour change — 2026-06-03
- File: `lib/syntax.ex`
- Reason: change is not OK as-is (judged in isolation). The `apply_rules_traced/2`
  extraction is a clean DRY refactor, but the behaviour change — run syntax rules
  even when the source already parses — ships two defects:
  1. Stale docs: the moduledoc ("Only runs when `Sourceror.parse_string/1` fails")
     and the `fix_with_trace/2` @doc ("If the source already parses, the pipeline
     is skipped entirely") now contradict the actual behaviour.
  2. No safety net on the now-active `{:ok}` branch: it returns `{fixed, applied}`
     with no parse-verify (the `{:error}` branch at least re-parses, log-only), so
     valid, parseable code can be turned into non-parsing code silently.
- Suggested action: rewrite the two doc blocks; add a parse-verify on the `{:ok}`
  branch and decide whether a non-parsing `fixed` should fall back to `source`.
  Also coupled to the wider syntax-subsystem change (4 new fixers + runner + tests),
  so review alongside those.
