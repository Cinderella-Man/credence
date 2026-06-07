defmodule Credence.RuleCase do
  @moduledoc """
  The one case template every per-rule test uses. `use Credence.RuleCase` (add
  `async: true` to opt in) brings in `ExUnit.Case`, the rule-firing/​rule-fixing
  verbs below, and the behaviour-equivalence harness — so a `_check_test.exs`,
  `_fix_test.exs`, and `_equivalence_test.exs` all start with the same line and
  reach for the same tools.

  The rule is passed to each verb (not bound at `use` time), so a file that
  touches more than one rule, or a helper that takes a rule, reads the same way:

      use Credence.RuleCase, async: true
      alias Credence.Pattern.NoFoo

      test "flags and rewrites" do
        assert flagged?(NoFoo, "...")
        assert fix(NoFoo, "...") == "...\\n"
      end

  ## Why these verbs live in one place

  Before this template, all 113 `_check_test.exs` re-declared a local
  `defp check/1` and all 114 `_fix_test.exs` re-declared a `defp fix/1` — and the
  fix helper had drifted into several incompatible shapes (raw patch,
  trailing-newline normalize, `Code.format_string!` re-format, and a hand-rolled
  `Sourceror.patch_string` that skipped the production apply path entirely). The
  "apply the fix and compare" decision now lives here once.

  ## `fix/2` is byte-exact

  `fix/2` returns the bytes the pipeline actually ships — `apply_rule_fix/3`
  (`fix_patches/2` → `Sourceror.patch_string/2`), verbatim, no re-formatting. The
  `expected` string is therefore exactly what the AI would receive.

  This is deliberate. Re-formatting the output before comparing would test bytes
  production never emits, and would *launder* a rule that re-indents or reflows
  lines it never touched (the formatter quietly tidies the damage). Byte-exact
  compare catches such a layout regression for free: the mangled line simply won't
  match `expected`. The flip side is that a rule which emits non-`mix format`-clean
  code (e.g. a long unwrapped line) shows that real output in its `expected` — a
  truthful signal, not something to hide.
  """

  use ExUnit.CaseTemplate

  alias Credence.RuleHelpers

  using do
    quote do
      import Credence.RuleCase
      import Credence.BehaviourEquivalence
    end
  end

  @doc """
  Parse `code` with Sourceror and run `rule`'s `check/2`, returning its issues.
  `:source` is passed through (production always supplies it), so a check that
  reads the raw bytes behaves as it does in the pipeline.
  """
  def check(rule, code) do
    ast = Sourceror.parse_string!(code)
    rule.check(ast, source: code)
  end

  @doc "True when `rule` flags `code` (its `check/2` returns at least one issue)."
  def flagged?(rule, code), do: check(rule, code) != []

  @doc "True when `rule` leaves `code` alone (its `check/2` returns no issues)."
  def clean?(rule, code), do: check(rule, code) == []

  @doc """
  Apply `rule`'s fix to `code` the way the pipeline does and return the resulting
  source, byte-exact (see the module doc).

  `opts` is forwarded to `RuleHelpers.apply_rule_fix/3` — for the few rules whose
  fix takes a strategy (e.g. `fix_strategy: :reduce`).
  """
  def fix(rule, code, opts \\ []) do
    RuleHelpers.apply_rule_fix(rule, code, opts)
  end
end
