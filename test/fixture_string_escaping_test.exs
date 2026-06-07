defmodule Credence.FixtureStringEscapingTest do
  @moduledoc """
  The gate that keeps every **code fixture** a `\"""` heredoc — never an escaped
  `"...\\n..."` / `"...\\""` string, a `~s`/`~S` sigil, or a `"a" <> "b"`
  concatenation (a common way to sneak a multi-line string past the rule).

  Scoped to **fixture positions** (the code-under-test): a string passed to a rule
  verb (`check`/`fix`/`clean?`/…/`assert_equivalent`), compared to one with `==`,
  or assigned to `code`/`input`/`expected`/`source`/…. Non-fixtures — a `=~`
  message-substring, a `mark_equivalence_*` reason, a `\#{}` fragment in a list —
  are not checked; they legitimately stay plain.

  Introspected with Sourceror (delimiter-aware). A fixture is OK when it's a
  heredoc, a `~S\"""...\"""` sigil-heredoc (also triple quotes, raw for `\#{}` code),
  an interpolated string/sigil, or code that contains `\"""` (can't nest in a
  heredoc). Plus a tiny file allow-list for fixtures a heredoc breaks structurally.
  """
  use ExUnit.Case, async: true

  import Credence.MetaTestSupport

  @dirs ["test/pattern", "test/semantic", "test/syntax"]

  @verbs MapSet.new([
           :check,
           :flagged?,
           :clean?,
           :fix,
           :valid_syntax?,
           :compiles?,
           :analyze,
           :assert_equivalent,
           :assert_equivalent_module,
           :assert_effect_trace_equivalent
         ])

  @fvars MapSet.new([:code, :input, :expected, :source, :fixed, :snippet, :before, :after])

  @allow %{
    "test/pattern/no_redundant_binary_syntax_fix_test.exs" =>
      "the fix reprints the whole expression, dropping the input's trailing " <>
        "newline; a heredoc expected (which has one) can't match, and the quoted " <>
        "result has no heredoc/sigil-free form",
    "test/semantic/missing_use_exunit_case_fix_test.exs" =>
      "the fix forces a trailing blank line; mix format trims a heredoc's, changing the value"
  }

  defp files do
    @dirs |> Enum.flat_map(&Path.wildcard("#{&1}/**/*_test.exs")) |> Enum.sort()
  end

  # Collect string-like nodes sitting in a fixture position.
  defp fixtures(ast) do
    {_, acc} =
      Macro.prewalk(ast, [], fn node, acc ->
        add =
          case node do
            {op, _, [l, r]} when op in [:==, :!=] ->
              if verb_call?(l) or verb_call?(r), do: Enum.filter([l, r], &stringish?/1), else: []

            {:=, _, [{var, _, ctx}, rhs]} when is_atom(var) and is_atom(ctx) ->
              if MapSet.member?(@fvars, var) and stringish?(rhs), do: [rhs], else: []

            {v, _, args} when is_atom(v) and is_list(args) ->
              if MapSet.member?(@verbs, v), do: Enum.filter(args, &stringish?/1), else: []

            _ ->
              []
          end

        {node, add ++ acc}
      end)

    Enum.uniq(acc)
  end

  defp stringish?({:__block__, m, [s]}) when is_binary(s), do: Keyword.get(m, :delimiter) != nil
  defp stringish?({:<<>>, _, _}), do: true
  defp stringish?({sg, _, _}) when sg in [:sigil_s, :sigil_S], do: true
  defp stringish?({:<>, _, [l, r]}), do: stringish?(l) and stringish?(r)
  defp stringish?(_), do: false

  defp verb_call?({v, _, a}) when is_atom(v) and is_list(a), do: MapSet.member?(@verbs, v)
  defp verb_call?(_), do: false

  # A fixture is acceptable when it's already a heredoc form, interpolated, or
  # carries code containing `"""` (which a heredoc can't nest).
  defp ok?({:__block__, m, [s]}) when is_binary(s) do
    Keyword.get(m, :delimiter) == "\"\"\"" or
      String.contains?(String.replace(s, "\\\"", "\""), "\"\"\"")
  end

  # interpolated string
  defp ok?({:<<>>, _, _}), do: true

  defp ok?({sg, m, [{:<<>>, _, [b]}, _]}) when sg in [:sigil_s, :sigil_S] and is_binary(b),
    do: Keyword.get(m, :delimiter) == "\"\"\"" or String.contains?(b, "\"\"\"")

  # interpolated sigil
  defp ok?({sg, _, _}) when sg in [:sigil_s, :sigil_S], do: true
  # a "a" <> "b" concatenation is never a heredoc
  defp ok?({:<>, _, _}), do: false
  defp ok?(_), do: false

  test "every code fixture is a heredoc — no escaped string, sigil, or <> concat" do
    bad =
      for path <- files(),
          not Map.has_key?(@allow, path),
          {:ok, ast} = load_ast(path),
          node <- fixtures(ast),
          not ok?(node),
          uniq: true,
          do: path

    assert Enum.uniq(bad) == [],
           "fixtures that aren't heredocs (use a \"\"\" heredoc):\n" <>
             Enum.map_join(Enum.uniq(bad), "\n", &("  - " <> &1))
  end
end
