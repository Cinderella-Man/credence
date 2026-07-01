defmodule Credence.DslMacroProtectionTest do
  @moduledoc """
  Behavioural guard: every rule that declares `unsafe_in_dsl/0` is *shown* to leave
  the macro untouched.

  The classification guard (`Credence.Pattern.DslSafetyClassificationTest`) proves
  the right rules are *flagged*; this proves the flag actually *protects the macro*,
  rule by rule. For every flagged rule it takes the rule's own `*_fix_test.exs`
  `input` fixtures (the anti-pattern the fix targets), embeds each inside one of the
  DSL families the rule is declared unsafe in (an `Nx` `defn` body, an `Ash` `expr`,
  or an `Ecto` query), and asserts the full fix leaves that source **byte-identical**
  — i.e. the gate dropped the in-macro patch.

  Two things are asserted:

    * **No leak** — for every embedded fixture where the rule actually fires inside
      the detected DSL block, `apply_rule_fix/3` must return the source unchanged.
      A change means a rule rewrote inside a macro it is flagged not to touch.
    * **No vacuous coverage** — every flagged rule must have at least one fixture
      that fires inside an embedded block (so the guard is not silently empty for
      it). If a new flagged rule's fixtures cannot be embedded, this fails and the
      author must add an embeddable fixture.

  Discovers flagged rules dynamically, so a newly-flagged rule is covered the moment
  it declares `unsafe_in_dsl/0`. Lives at `test/` root with the other meta-tests
  (the `test/pattern` parser gate forbids the `Sourceror`/`Code` calls used here).
  """
  use ExUnit.Case, async: true

  alias Credence.{DslGuard, Pattern, RuleHelpers}

  defp flagged_rules do
    Pattern.default_rules()
    |> Enum.filter(&(function_exported?(&1, :unsafe_in_dsl, 0) and &1.unsafe_in_dsl() != []))
  end

  # Normalise `:all` to the concrete family list, then pick the family whose
  # wrapper most reliably embeds an arbitrary fixture (defn bodies accept
  # statement sequences; expr/where accept a single expression).
  defp embed_family(rule) do
    families =
      case rule.unsafe_in_dsl() do
        :all -> DslGuard.families()
        list -> list
      end

    cond do
      :nx_defn in families -> :nx_defn
      :ash_expr in families -> :ash_expr
      :ecto_query in families -> :ecto_query
      true -> hd(families)
    end
  end

  defp wrap(fixture, family) do
    body = fixture |> String.trim_trailing() |> indent(2)
    expr_body = fixture |> String.trim_trailing() |> indent(4)

    case family do
      :nx_defn -> "defn __probe__(a, b, c, d, e, f, g, h) do\n#{body}\nend\n"
      :ash_expr -> "def __probe__ do\n  expr(\n#{expr_body}\n  )\nend\n"
      :ecto_query -> "def __probe__(query) do\n  where(query, [a, b, c],\n#{expr_body}\n  )\nend\n"
    end
  end

  defp indent(s, n) do
    pad = String.duplicate(" ", n)
    s |> String.split("\n") |> Enum.map_join("\n", &(pad <> &1))
  end

  test "every rule flagged unsafe_in_dsl is gated out of the macro (no leak, no vacuous coverage)" do
    rules = flagged_rules()
    assert rules != [], "expected at least one rule to declare unsafe_in_dsl/0"

    {leaks, uncovered} =
      Enum.reduce(rules, {[], []}, fn rule, {leaks, uncovered} ->
        name = Macro.underscore(RuleHelpers.rule_name(rule))
        family = embed_family(rule)
        fixtures = fixture_inputs(name)

        outcomes =
          for fixture <- fixtures, wrapped = wrap(fixture, family), reduce: [] do
            acc ->
              case probe(rule, wrapped) do
                :fired_and_gated -> [:ok | acc]
                :leaked -> [{:leak, wrapped} | acc]
                :inert -> acc
              end
          end

        leaks =
          for({:leak, src} <- outcomes, do: {name, family, src}) ++ leaks

        covered? = Enum.any?(outcomes, &(&1 == :ok))
        uncovered = if covered?, do: uncovered, else: [{name, family} | uncovered]

        {leaks, uncovered}
      end)

    assert leaks == [], leak_message(leaks)

    assert uncovered == [],
           "These flagged rules were never exercised inside an embedded DSL block (the guard " <>
             "is vacuous for them — add an embeddable fixture, or check the embedding family):\n" <>
             Enum.map_join(uncovered, "\n", fn {n, f} -> "  - #{n} (#{f})" end)
  end

  # Outcome of embedding one fixture: did the rule fire inside the block, and if so
  # did the gate stop the fix?
  defp probe(rule, wrapped) do
    with {:ok, ast} <- Sourceror.parse_string(wrapped),
         true <- DslGuard.block_ranges(ast) != [],
         true <- rule.check(ast, source: wrapped) != [] do
      if RuleHelpers.apply_rule_fix(rule, wrapped) == wrapped, do: :fired_and_gated, else: :leaked
    else
      _ -> :inert
    end
  rescue
    _ -> :inert
  end

  defp fixture_inputs(name) do
    file = "test/pattern/#{name}_fix_test.exs"

    with true <- File.exists?(file),
         {:ok, ast} <- Code.string_to_quoted(File.read!(file)) do
      {_ast, acc} =
        Macro.prewalk(ast, [], fn
          {:=, _, [{:input, _, ctx}, node]}, acc when is_atom(ctx) ->
            case string_value(node) do
              nil -> {node, acc}
              str -> {node, [str | acc]}
            end

          node, acc ->
            {node, acc}
        end)

      Enum.reverse(acc)
    else
      _ -> []
    end
  end

  defp string_value({:__block__, _, [s]}) when is_binary(s), do: s
  defp string_value(s) when is_binary(s), do: s
  defp string_value(_), do: nil

  defp leak_message(leaks) do
    "These flagged rules rewrote code INSIDE a macro block their `unsafe_in_dsl/0` " <>
      "says they must not touch — the DSL gate failed to protect it:\n" <>
      Enum.map_join(leaks, "\n\n", fn {name, family, src} ->
        "  • #{name} (#{family}) changed:\n" <> indent(src, 6)
      end)
  end
end
