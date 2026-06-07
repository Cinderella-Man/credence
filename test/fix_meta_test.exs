defmodule Credence.FixMetaTest do
  @moduledoc """
  The substance gate for every rule's `_fix_test.exs`. `RuleTestCompletenessTest`
  proves the file exists and is named right; this proves it actually *tests the
  fix*, the way the project requires:

    1. **Real fix assertion** — calls `fix(Rule, …)`. A hollow file no longer passes.
    2. **References its rule** — so a copy-paste can't test the wrong rule.
    3. **Whole-string `==` only** — no `=~`, `String.contains?`, `Regex.match?`,
       `String.starts_with?`/`ends_with?`, and no `normalize_sourceror_ast`
       round-trip (the old `norm`/`assert_fix` laundering). A fix must be pinned to
       its exact bytes; a partial or normalized match lets an unintended change
       elsewhere slip through. (The [[rule-test-style]] policy, enforced by the
       build instead of by review.)
    4. **At least one real transform** — an `fix(Rule, A) == B` where `B ≠ A`, so a
       file made entirely of `fix(Rule, code) == code` no-ops can't pass without
       proving the fix rewrites anything.

  Detection is shape-based (Sourceror), so heredoc fixtures — which legitimately
  contain `=~`, `Regex.match?`, etc. as *test input* — are invisible here; only
  real assertion nodes are inspected.
  """
  use ExUnit.Case, async: true

  import Credence.MetaTestSupport

  @banned_matchers [:contains?, :starts_with?, :ends_with?, :match?]

  defp fix_call?({:fix, _, [_rule | [_code | _]]}), do: true
  defp fix_call?(_), do: false

  # `=~`, an AST-normalizing round-trip (`normalize_sourceror_ast`, which the old
  # `norm`/`assert_fix` helpers routed through), or a qualified String/Regex
  # partial matcher — all in real test logic, not inside a heredoc fixture.
  defp partial_match?({:=~, _, _}), do: true

  defp partial_match?({{:., _, [{:__aliases__, _, mods}, :normalize_sourceror_ast]}, _, _})
       when is_list(mods),
       do: true

  defp partial_match?({{:., _, [{:__aliases__, _, [mod]}, fun]}, _, _})
       when mod in [:String, :Regex] and fun in @banned_matchers,
       do: true

  defp partial_match?(_), do: false

  # `fix(Rule, A) == B` where B is not structurally A — i.e. the fix changed something.
  defp transform?({:==, _, [a, b]}) do
    case {fix_call?(a), fix_call?(b)} do
      {true, _} -> fix_arg(a) != src(b)
      {_, true} -> fix_arg(b) != src(a)
      _ -> false
    end
  end

  defp transform?(_), do: false

  defp fix_arg({:fix, _, [_rule, code | _]}), do: src(code)

  defp analyze(rule) do
    path = test_path(rule, "fix")

    case load_ast(path) do
      {:ok, ast} ->
        %{
          rule: rule,
          path: path,
          asserts: calls_any?(ast, [:fix]),
          references_rule: references_rule?(ast, String.to_atom(short(rule))),
          whole_string: not walk_any?(ast, &partial_match?/1),
          has_transform: walk_any?(ast, &transform?/1)
        }

      :error ->
        %{rule: rule, path: path, asserts: false, references_rule: false, whole_string: false, has_transform: false}
    end
  end

  defp analyses, do: Enum.map(rules(), &analyze/1)

  test "every fix test makes a real fix assertion" do
    bad = Enum.reject(analyses(), & &1.asserts)

    assert bad == [],
           "fix tests that never call fix/2 (hollow):\n" <>
             bullets(bad, fn a -> "#{inspect(a.rule)} — #{a.path}" end)
  end

  test "every fix test references the rule it covers" do
    bad = Enum.reject(analyses(), & &1.references_rule)

    assert bad == [],
           "fix tests that never reference their rule module (may test the wrong rule):\n" <>
             bullets(bad, fn a -> "#{inspect(a.rule)} — #{a.path}" end)
  end

  test "every fix test compares whole strings (no =~ / substring / normalize)" do
    bad = Enum.reject(analyses(), & &1.whole_string)

    assert bad == [],
           "fix tests using a partial or normalized comparison instead of whole-string ==:\n" <>
             bullets(bad, fn a -> "#{inspect(a.rule)} — #{a.path}" end)
  end

  test "every fix test exercises at least one real transformation (not all no-ops)" do
    bad = Enum.reject(analyses(), & &1.has_transform)

    assert bad == [],
           "fix tests with no `fix(rule, input) == expected` where expected differs from input:\n" <>
             bullets(bad, fn a -> "#{inspect(a.rule)} — #{a.path}" end)
  end
end
