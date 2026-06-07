defmodule Credence.FixtureStringEscapingTest do
  @moduledoc """
  The gate that keeps code fixtures as **heredocs** — no escaping, no sigils. A
  test under `test/pattern`/`test/semantic`/`test/syntax` writes code-under-test in
  a `\"""` heredoc, never a `"...\\n..."` / `"...\\""` escaped string and never a
  `~s`/`~S` sigil.

  Introspected with Sourceror (delimiter-aware). Exempt — things a heredoc can't
  carry:

    * the `test`/`describe` **name**;
    * code containing `\"""` (closes the heredoc);
    * an **interpolated** fixture (`~s[...\#{x}...]`, a multi-part sigil) — kept as a
      sigil so the interpolation survives.

  Plus a small, reasoned **file allow-list** for fixtures a heredoc breaks for a
  reason it can't express structurally (the fix drops/transforms the trailing
  newline, the diagnostic is line-number-sensitive, or the expected ends in a
  blank line `mix format` would trim).
  """
  use ExUnit.Case, async: true

  import Credence.MetaTestSupport

  @dirs ["test/pattern", "test/semantic", "test/syntax"]

  @allow %{
    "test/pattern/no_redundant_binary_syntax_fix_test.exs" =>
      "the fix reprints the whole expression, dropping the input's trailing " <>
        "newline; a heredoc expected (which has one) can't match, and the quoted " <>
        "result has no sigil-free single-line form",
    "test/semantic/undefined_function_local_fix_test.exs" =>
      "the diagnostic targets a specific source line; a heredoc shifts line numbers",
    "test/semantic/missing_use_exunit_case_fix_test.exs" =>
      "the fix forces a trailing blank line; mix format trims a heredoc's, changing the value",
    "test/pattern/no_guard_equality_for_pattern_match_check_test.exs" =>
      "asserts on message *substrings* via `=~` (`s == \"zero\"`); a heredoc's " <>
        "trailing newline would break the substring match",
    "test/pattern/no_dead_map_update_check_test.exs" =>
      "builds fixtures by interpolating a list of literal-default *fragments* " <>
        "(`\"\"`); these are not standalone fixtures"
  }

  defp files do
    @dirs |> Enum.flat_map(&Path.wildcard("#{&1}/**/*_test.exs")) |> Enum.sort()
  end

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

  # Multi-line code crammed into a normal "..." string.
  defp multiline_string?({:__block__, meta, [v]}, names) when is_binary(v) do
    unescaped = String.replace(v, "\\\"", "\"")
    pure_ws? = v |> String.replace("\\n", "") |> String.trim() == ""

    Keyword.get(meta, :delimiter) == "\"" and String.contains?(v, "\\n") and
      not MapSet.member?(names, v) and not String.contains?(unescaped, "\"\"\"") and
      not String.contains?(v, "\#{") and not String.ends_with?(v, "\\n\\n") and not pure_ws?
  end

  defp multiline_string?(_node, _names), do: false

  # Single-line normal "..." string with a nested quote (a `\"` escape).
  defp escaped_quote?({:__block__, meta, [v]}, names) when is_binary(v) do
    Keyword.get(meta, :delimiter) == "\"" and String.contains?(v, "\"") and
      not String.contains?(v, "\\n") and not MapSet.member?(names, v)
  end

  defp escaped_quote?(_node, _names), do: false

  # A `~s`/`~S` sigil that should be a plain heredoc: single (non-interpolated)
  # part, code free of `\"""`, and NOT already a triple-quote sigil-heredoc
  # (`~S\"""..."""`, which *is* triple quotes — used raw when the code has `\#{}`).
  defp sigil?({sg, meta, [{:<<>>, _, [bin]}, _]}, _names)
       when sg in [:sigil_s, :sigil_S] and is_binary(bin),
       do: Keyword.get(meta, :delimiter) != "\"\"\"" and not String.contains?(bin, "\"\"\"")

  defp sigil?(_node, _names), do: false

  defp offenders(pred) do
    files()
    |> Enum.reject(&Map.has_key?(@allow, &1))
    |> Enum.filter(fn path ->
      {:ok, ast} = load_ast(path)
      names = block_names(ast)
      walk_any?(ast, &pred.(&1, names))
    end)
  end

  test "multi-line code fixtures use heredocs, not escaped \"...\\n...\" strings" do
    assert offenders(&multiline_string?/2) == [],
           "use a heredoc:\n" <> list(offenders(&multiline_string?/2))
  end

  test "no \\\" escaped-quote fixtures — use a heredoc" do
    assert offenders(&escaped_quote?/2) == [],
           "escaped quote — use a heredoc:\n" <> list(offenders(&escaped_quote?/2))
  end

  test "no ~s/~S sigil fixtures — use a heredoc" do
    assert offenders(&sigil?/2) == [],
           "sigil fixture — use a heredoc:\n" <> list(offenders(&sigil?/2))
  end

  defp list(paths), do: Enum.map_join(paths, "\n", &("  - " <> &1))
end
