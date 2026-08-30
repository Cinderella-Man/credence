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
        confirm_fix(fix(NoFoo, "..."), "...")
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

  import ExUnit.Assertions

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

  @doc """
  Assert `actual` (a fix result) equals `expected`, ignoring **trailing
  newlines** on both sides. The canonical fix-test assertion:

      confirm_fix(fix(NoFoo, input), expected)

  A single-line fixture may be written as a compact `"…"` (no newline) or a
  heredoc (which always appends one), and `mix format` normalizes either way — so
  the trailing newline is incidental and not compared. Internal layout is still
  compared byte-exact (re-indentation / reflow still fails the assertion).
  """
  def confirm_fix(actual, expected) do
    assert String.trim_trailing(actual, "\n") == String.trim_trailing(expected, "\n")
  end

  @doc """
  True when `code` parses as valid Elixir, via Sourceror (the project's only
  parser). Lets a test assert a fix produced parseable output without reaching
  for `Sourceror`/`Code` itself.
  """
  def valid_syntax?(code), do: match?({:ok, _}, Sourceror.parse_string(code))

  @doc """
  The `@doc` strings, `@spec`s and `def` clauses `code` actually carries, in
  source order, as `%{docs: [...], specs: [...], defs: [{name, arity}, ...]}`.

  Use it to assert what emitted source *means* where "it parses" is not enough:
  a repair that truncates a doc, folds an `@spec` into the doc string, or turns a
  documented example into a live extra clause still parses and still compiles
  without a warning. Reads the shape back off the source itself so the test never
  reaches for the parser.
  """
  def module_shape(code) do
    {:ok, ast} = Code.string_to_quoted(code)

    {_ast, shape} =
      Macro.prewalk(ast, %{docs: [], specs: [], defs: []}, fn
        {:@, _, [{:doc, _, [text]}]} = node, acc when is_binary(text) ->
          {node, %{acc | docs: acc.docs ++ [text]}}

        {:@, _, [{:spec, _, [spec]}]} = node, acc ->
          {node, %{acc | specs: acc.specs ++ [Macro.to_string(spec)]}}

        {:def, _, [{:when, _, [{name, _, args} | _]} | _]} = node, acc when is_atom(name) ->
          {node, %{acc | defs: acc.defs ++ [{name, length(args || [])}]}}

        {:def, _, [{name, _, args} | _]} = node, acc when is_atom(name) ->
          {node, %{acc | defs: acc.defs ++ [{name, length(args || [])}]}}

        node, acc ->
          {node, acc}
      end)

    shape
  end

  @doc """
  True when `code` compiles. Use to assert a fix turned non-compiling input
  (e.g. an attribute outside a module) into a compiling module — hiding the
  `Code.compile_string` reach from the test.
  """
  def compiles?(code) do
    match?({:ok, _diagnostics}, RuleHelpers.compile_and_capture(code))
  end

  @doc """
  Compiles `code`, calls `module.fun(args)`, and returns the result. The module
  is purged afterwards so repeated fixtures do not leak between tests.

  Use this to assert what a fix *means*, not just what it looks like. A repair
  that drops a branch — emitting a discarded expression where an early exit was
  written — still compiles, still parses, and still satisfies every string
  comparison in a test file. Only running the result catches it. That is not
  hypothetical: two tests in this suite asserted exactly such an output as
  correct, and passed for as long as the defect shipped.

  The fixture module name must be unique across the suite, since compiling it
  redefines any module of the same name.
  """
  def call_fixed(code, module, fun, args) do
    {:ok, _diagnostics} = RuleHelpers.compile_and_capture(code, cleanup_modules: false)
    apply(module, fun, args)
  after
    :code.purge(module)
    :code.delete(module)
  end
end
