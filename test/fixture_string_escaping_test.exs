defmodule Credence.FixtureStringEscapingTest do
  @moduledoc """
  The gate that keeps code fixtures free of string escaping. A test under
  `test/pattern`/`test/semantic`/`test/syntax` may not write code-under-test as a
  double-quoted string that needs `\\n` or `\\"` escaping to read through:

    * **multi-line** code → use a `\"""` heredoc, not `"defmodule M do\\n  ...\\nend"`;
    * **a nested quote** → use a `~s` sigil, not `"Enum.join(list, \\"\\")"`.

  Introspected with Sourceror (delimiter-aware), so heredocs, sigils, and clean
  single-line strings are exempt automatically. Also exempt — things those forms
  genuinely can't carry:

    * the `test`/`describe` **name** (can't be a heredoc/sigil);
    * code containing `\"""` (closes the heredoc) or `\#{` (a heredoc interpolates it);
    * a string ending in a **blank line** (`\\n\\n`) — `mix format` trims a heredoc's
      trailing blank, changing the value;
    * a pure-whitespace string (`"\\n"` separator, not a fixture).

  Plus a tiny, reasoned allow-list for fixtures a heredoc would break structurally.
  """
  use ExUnit.Case, async: true

  import Credence.MetaTestSupport

  @dirs ["test/pattern", "test/semantic", "test/syntax"]

  # Files exempt with a reason (heredoc conversion breaks them structurally).
  @allow %{
    "test/semantic/undefined_function_local_fix_test.exs" =>
      "the diagnostic targets a specific source line; a heredoc shifts line " <>
        "numbers, so the local-call fix no longer lands"
  }

  defp files do
    @dirs |> Enum.flat_map(&Path.wildcard("#{&1}/**/*_test.exs")) |> Enum.sort()
  end

  # Names of test/describe blocks — can't be a heredoc/sigil.
  defp block_names(ast) do
    {_, acc} =
      Macro.prewalk(ast, [], fn
        {k, _, [{:__block__, _, [n]} | _]} = node, acc
        when k in [:test, :describe] and is_binary(n) ->
          {node, [n | acc]}

        node, acc ->
          {node, acc}
      end)

    MapSet.new(acc)
  end

  # Multi-line code crammed into a normal "..." string that a heredoc could carry.
  defp multiline_string?({:__block__, meta, [v]}, names) when is_binary(v) do
    unescaped = String.replace(v, "\\\"", "\"")
    pure_ws? = v |> String.replace("\\n", "") |> String.trim() == ""

    Keyword.get(meta, :delimiter) == "\"" and
      String.contains?(v, "\\n") and
      not MapSet.member?(names, v) and
      not String.contains?(unescaped, "\"\"\"") and
      not String.contains?(v, "\#{") and
      not String.ends_with?(v, "\\n\\n") and
      not pure_ws?
  end

  defp multiline_string?(_node, _names), do: false

  # A single-line normal "..." string with a nested quote (i.e. a `\"` escape;
  # Sourceror decodes it, so the value carries a literal `"`). Use a `~s` sigil.
  defp escaped_quote?({:__block__, meta, [v]}, names) when is_binary(v) do
    Keyword.get(meta, :delimiter) == "\"" and
      String.contains?(v, "\"") and
      not String.contains?(v, "\\n") and
      not MapSet.member?(names, v)
  end

  defp escaped_quote?(_node, _names), do: false

  defp targets do
    files() |> Enum.reject(&Map.has_key?(@allow, &1))
  end

  defp offenders(pred) do
    Enum.filter(targets(), fn path ->
      {:ok, ast} = load_ast(path)
      names = block_names(ast)
      walk_any?(ast, &pred.(&1, names))
    end)
  end

  test "multi-line code fixtures use heredocs, not escaped \"...\\n...\" strings" do
    bad = offenders(&multiline_string?/2)

    assert bad == [],
           "multi-line code crammed into a \"...\\n...\" string — use a heredoc:\n" <>
             Enum.map_join(bad, "\n", &("  - " <> &1))
  end

  test "single-line fixtures with a nested quote use a ~s sigil, not \\\" escaping" do
    bad = offenders(&escaped_quote?/2)

    assert bad == [],
           "fixture with a \\\" escaped quote — use a ~s sigil (e.g. ~s[foo(\"a\")]):\n" <>
             Enum.map_join(bad, "\n", &("  - " <> &1))
  end
end
