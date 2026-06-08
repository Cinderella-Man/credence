defmodule Credence.SyntaxMetaTest do
  @moduledoc """
  The substance gate for Syntax rules — the analogue of the Pattern gates, so a
  Syntax rule can no longer ship inert or untested. For each discovered
  `Credence.Syntax.Rule`, its test files (any file under `test/syntax` that
  references the rule — one combined file or a split `_analyze`/`_fix` pair, both
  are fine) must, across their union, prove the rule actually does something:

    1. **Has tests** — at least one test file references the rule.
    2. **`analyze` in both directions** — a positive case (`analyze(...)` used as
       non-empty) and a negative case (`analyze(...) == []`). One direction alone
       is blind to over- or under-firing.
    3. **A real fix** — at least one `fix(A) == B` where `B ≠ A`, so a file of
       `fix(x) == x` no-ops can't pass.
    4. **The fix reaches a fixpoint** — an `analyze(fix(...)) == []` assertion, so
       the fix provably clears the very thing `analyze` flags (not just changes
       bytes).

  Attribution (the issue's `rule:` atom) is intentionally *not* gated here: unlike
  Pattern/Semantic, a Syntax rule's atom is author-chosen and unrelated to the
  module name (e.g. `FixPythonModulo` reports `:python_modulo`), so a generic
  convention check would be wrong.

  Detection is shape-based (Sourceror); helpers live in `Credence.MetaTestSupport`
  so the generator pin asserts against this same code.
  """
  use ExUnit.Case, async: true

  import Credence.MetaTestSupport

  defp attributed(rule) do
    short_atom = String.to_atom(short(rule))

    "test/syntax/**/*_test.exs"
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      case load_ast(path) do
        {:ok, ast} -> if references_rule?(ast, short_atom), do: [ast], else: []
        :error -> []
      end
    end)
  end

  defp report(rule) do
    asts = attributed(rule)

    %{
      rule: rule,
      has_files: asts != [],
      positive: Enum.any?(asts, &analyze_positive?/1),
      negative: Enum.any?(asts, &analyze_negative?/1),
      transform: Enum.any?(asts, fn ast -> walk_any?(ast, &fix_source_transform?/1) end),
      fixpoint: Enum.any?(asts, fn ast -> walk_any?(ast, &fixpoint?/1) end)
    }
  end

  defp reports, do: Enum.map(syntax_rules(), &report/1)

  test "every Syntax rule has at least one test file" do
    bad = Enum.reject(reports(), & &1.has_files)

    assert bad == [],
           "Syntax rules with no test file referencing them:\n" <>
             bullets(bad, fn r -> inspect(r.rule) end)
  end

  test "every Syntax rule's analyze is tested in both directions" do
    bad = Enum.reject(reports(), fn r -> r.positive and r.negative end)

    assert bad == [],
           "Syntax rules whose analyze test is missing a direction:\n" <>
             bullets(bad, fn r ->
               missing =
                 [
                   {r.positive, "positive (analyze used non-empty)"},
                   {r.negative, "negative (analyze == [])"}
                 ]
                 |> Enum.reject(&elem(&1, 0))
                 |> Enum.map_join(" and ", &elem(&1, 1))

               "#{inspect(r.rule)} — missing #{missing}"
             end)
  end

  test "every Syntax rule exercises at least one real fix transformation" do
    bad = Enum.reject(reports(), & &1.transform)

    assert bad == [],
           "Syntax rules with no `fix(input) == expected` where expected differs from input:\n" <>
             bullets(bad, fn r -> inspect(r.rule) end)
  end

  test "every Syntax rule proves its fix reaches a fixpoint (analyze(fix(x)) == [])" do
    bad = Enum.reject(reports(), & &1.fixpoint)

    assert bad == [],
           "Syntax rules with no analyze(fix(x)) == [] assertion (the fix must clear its own flag):\n" <>
             bullets(bad, fn r -> inspect(r.rule) end)
  end
end
