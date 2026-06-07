defmodule Credence.CheckMetaTest do
  @moduledoc """
  The substance gate for every rule's `_check_test.exs`. `RuleTestCompletenessTest`
  proves the file exists and is named right; this proves it actually *tests the
  check*, in both directions:

    1. **Real check assertion** — calls `check` / `flagged?` / `clean?`. A file
       that exists but asserts nothing no longer passes.
    2. **References its rule** — uses the rule module (e.g. `flagged?(NoFoo, …)`),
       so a copy-paste can't quietly test the wrong rule.
    3. **Both directions** — at least one *positive* case (the rule fires) AND at
       least one *negative* case (the rule stays quiet). A check test with only
       positive cases is blind to over-firing; only-negative is blind to
       under-firing.

  A rule that genuinely cannot flag-and-not-flag does not exist, so there is no
  opt-out here. Detection is shape-based (Sourceror), calibrated to the corpus —
  the failure message says how to satisfy it.
  """
  use ExUnit.Case, async: true

  import Credence.MetaTestSupport

  @check_fns [:check, :flagged?, :clean?]

  # A positive (rule-fires) assertion: an explicit `flagged?`, or a `check(...)`
  # result used as anything other than `== []` (bound to a list pattern, counted,
  # `hd`'d, compared `!= []`, …).
  defp has_positive?(ast) do
    calls_any?(ast, [:flagged?]) or
      count_nodes(ast, &check_call?/1) > count_nodes(ast, &check_eq_empty?/1)
  end

  # A negative (rule-stays-quiet) assertion: an explicit `clean?`, or `check(...) == []`.
  defp has_negative?(ast) do
    calls_any?(ast, [:clean?]) or count_nodes(ast, &check_eq_empty?/1) > 0
  end

  defp check_call?({:check, _, args}) when is_list(args), do: true
  defp check_call?(_), do: false

  defp check_eq_empty?({:==, _, [a, b]} = node),
    do: equals_empty_list?(node) and (check_call?(a) or check_call?(b))

  defp check_eq_empty?(_), do: false

  defp analyze(rule) do
    path = test_path(rule, "check")

    case load_ast(path) do
      {:ok, ast} ->
        %{
          rule: rule,
          path: path,
          asserts: calls_any?(ast, @check_fns),
          references_rule: references_rule?(ast, String.to_atom(short(rule))),
          positive: has_positive?(ast),
          negative: has_negative?(ast)
        }

      :error ->
        %{rule: rule, path: path, asserts: false, references_rule: false, positive: false, negative: false}
    end
  end

  defp analyses, do: Enum.map(rules(), &analyze/1)

  test "every check test makes a real check assertion" do
    bad = Enum.reject(analyses(), & &1.asserts)

    assert bad == [],
           "check tests that call no check/flagged?/clean? (hollow):\n" <>
             bullets(bad, fn a -> "#{inspect(a.rule)} — #{a.path}" end)
  end

  test "every check test references the rule it covers" do
    bad = Enum.reject(analyses(), & &1.references_rule)

    assert bad == [],
           "check tests that never reference their rule module (may test the wrong rule):\n" <>
             bullets(bad, fn a -> "#{inspect(a.rule)} — #{a.path}" end)
  end

  test "every check test has both a positive (flags) and a negative (does not flag) case" do
    bad = Enum.reject(analyses(), fn a -> a.positive and a.negative end)

    assert bad == [],
           "check tests missing a direction (a check must prove it BOTH fires and stays quiet):\n" <>
             bullets(bad, fn a ->
               missing =
                 [{a.positive, "positive (flagged?/non-empty check)"}, {a.negative, "negative (clean?/check == [])"}]
                 |> Enum.reject(&elem(&1, 0))
                 |> Enum.map_join(" and ", &elem(&1, 1))

               "#{inspect(a.rule)} — #{a.path} — missing #{missing}"
             end)
  end
end
