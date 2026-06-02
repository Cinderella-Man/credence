defmodule Credence.Pattern.NoStringSplitWhitespaceRegex do
  @moduledoc """
  Detects `String.split/2` or `String.split/3` with an explicit whitespace
  regex and suggests `String.split/1` instead.

  `String.split/1` (no arguments) already splits on any Unicode whitespace
  and trims leading/trailing empty entries. Passing `~r/\s+/` or
  `~r/\s/, trim: true` is redundant.

  ## Bad

      String.split(text, ~r/\s+/)
      String.split(text, ~r/\s/, trim: true)

  ## Good

      String.split(text)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case check_node(node) do
          {:ok, issue} -> {node, [issue | issues]}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, fn
      # 2-arg: String.split(x, ~r/\s+/) → String.split(x)
      {{:., d, [{:__aliases__, a, [:String]}, :split]}, m, [arg, regex]} = node ->
        if whitespace_plus_regex?(regex) do
          {{:., d, [{:__aliases__, a, [:String]}, :split]}, m, [arg]}
        else
          node
        end

      # 3-arg: String.split(x, ~r/\s/, trim: true) → String.split(x)
      {{:., d, [{:__aliases__, a, [:String]}, :split]}, m, [arg, regex, opts]} = node ->
        if whitespace_regex?(regex) and has_trim_true?(opts) do
          {{:., d, [{:__aliases__, a, [:String]}, :split]}, m, [arg]}
        else
          node
        end

      # 1-arg pipeline: |> String.split(~r/\s+/) → |> String.split()
      {{:., d, [{:__aliases__, a, [:String]}, :split]}, m, [regex]} = node ->
        if whitespace_plus_regex?(regex) do
          {{:., d, [{:__aliases__, a, [:String]}, :split]}, m, []}
        else
          node
        end

      node ->
        node
    end)
  end

  # Matches ~r/\s+/ (one-or-more whitespace) sigil
  defp whitespace_plus_regex?({:sigil_r, _, [{:<<>>, _, ["\\s+"]}, _modifiers]}), do: true
  defp whitespace_plus_regex?(_), do: false

  # Matches ~r/\s/ (single whitespace char) sigil
  defp whitespace_regex?({:sigil_r, _, [{:<<>>, _, ["\\s"]}, _modifiers]}), do: true
  defp whitespace_regex?(_), do: false

  defp check_node(
         {{:., _, [{:__aliases__, _, [:String]}, :split]}, meta, [_arg, regex]}
       ) do
    if whitespace_plus_regex?(regex) do
      {:ok, build_issue(meta)}
    else
      :error
    end
  end

  defp check_node(
         {{:., _, [{:__aliases__, _, [:String]}, :split]}, meta, [_arg, regex, opts]}
       ) do
    if whitespace_regex?(regex) and has_trim_true?(opts) do
      {:ok, build_issue(meta)}
    else
      :error
    end
  end

  defp check_node(
         {{:., _, [{:__aliases__, _, [:String]}, :split]}, meta, [regex]}
       ) do
    if whitespace_plus_regex?(regex) do
      {:ok, build_issue(meta)}
    else
      :error
    end
  end

  defp check_node(_), do: :error

  defp has_trim_true?([{:trim, true}]), do: true
  defp has_trim_true?([{{:__block__, _, [:trim]}, {:__block__, _, [true]}}]), do: true
  defp has_trim_true?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :no_string_split_whitespace_regex,
      message:
        "Use `String.split/1` instead of passing an explicit whitespace regex. " <>
          "`String.split/1` already splits on any whitespace and trims empty entries.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
