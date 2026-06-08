defmodule Credence.SemanticMetaTest do
  @moduledoc """
  The substance gate for Semantic rules — the analogue of the Pattern gates, so a
  Semantic rule can no longer ship inert or untested. For each discovered
  `Credence.Semantic.Rule`, its test files (any file under `test/semantic` that
  references the rule — a combined file, a `_check`/`_fix` pair, or a multi-file
  fix suite like `undefined_function`'s, all fine) must, across their union, prove
  the rule actually does something:

    1. **Has tests** — at least one test file references the rule.
    2. **`match?` in both directions** — `assert Rule.match?(...)` (it claims a
       diagnostic) and `refute Rule.match?(...)` (it ignores an unrelated one), so
       a rule that matches nothing — or everything — is caught.
    3. **Attribution** — the issue's `rule:` atom is pinned to the rule's own atom
       (e.g. `to_issue(diag).rule == :outdented_heredoc`), so a rule can't report
       its issues under the wrong name. (Semantic atoms follow the module name.)
    4. **A real fix** — at least one `fix(source, ...) == expected` where the
       output differs from the input.
    5. **The fix output is well-formed** — a `valid_syntax?(fix(...))` assertion,
       so a fix that rewrites the source into unparseable garbage is caught. (We
       use `valid_syntax?` rather than `compiles?`: the latter is false for correct
       fixes whose fixtures are bare `def`/expression fragments or need a running
       ExUnit context.)

  Detection is shape-based (Sourceror); helpers live in `Credence.MetaTestSupport`
  so the generator pin asserts against this same code.
  """
  use ExUnit.Case, async: true

  import Credence.MetaTestSupport

  alias Credence.RuleName

  defp attributed(rule) do
    short_atom = String.to_atom(short(rule))

    "test/semantic/**/*_test.exs"
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
    atom = RuleName.from_module(rule).atom

    %{
      rule: rule,
      has_files: asts != [],
      positive: Enum.any?(asts, &asserts_match?/1),
      negative: Enum.any?(asts, &refutes_match?/1),
      attribution: Enum.any?(asts, fn ast -> references_atom?(ast, atom) end),
      transform: Enum.any?(asts, fn ast -> walk_any?(ast, &fix_source_transform?/1) end),
      valid_output: Enum.any?(asts, fn ast -> walk_any?(ast, &fix_output_valid?/1) end)
    }
  end

  defp reports, do: Enum.map(semantic_rules(), &report/1)

  test "every Semantic rule has at least one test file" do
    bad = Enum.reject(reports(), & &1.has_files)

    assert bad == [],
           "Semantic rules with no test file referencing them:\n" <>
             bullets(bad, fn r -> inspect(r.rule) end)
  end

  test "every Semantic rule's match? is tested in both directions" do
    bad = Enum.reject(reports(), fn r -> r.positive and r.negative end)

    assert bad == [],
           "Semantic rules whose match? test is missing a direction:\n" <>
             bullets(bad, fn r ->
               missing =
                 [
                   {r.positive, "positive (assert match?)"},
                   {r.negative, "negative (refute match?)"}
                 ]
                 |> Enum.reject(&elem(&1, 0))
                 |> Enum.map_join(" and ", &elem(&1, 1))

               "#{inspect(r.rule)} — missing #{missing}"
             end)
  end

  test "every Semantic rule pins its issue attribution (to_issue(...).rule == :<atom>)" do
    bad = Enum.reject(reports(), & &1.attribution)

    assert bad == [],
           "Semantic rules whose tests never assert the issue's rule atom:\n" <>
             bullets(bad, fn r -> inspect(r.rule) end)
  end

  test "every Semantic rule exercises at least one real fix transformation" do
    bad = Enum.reject(reports(), & &1.transform)

    assert bad == [],
           "Semantic rules with no `fix(source, ...) == expected` where expected differs:\n" <>
             bullets(bad, fn r -> inspect(r.rule) end)
  end

  test "every Semantic rule proves its fix output is well-formed (valid_syntax?(fix(x)))" do
    bad = Enum.reject(reports(), & &1.valid_output)

    assert bad == [],
           "Semantic rules with no valid_syntax?(fix(x)) assertion (the fix output must parse):\n" <>
             bullets(bad, fn r -> inspect(r.rule) end)
  end
end
