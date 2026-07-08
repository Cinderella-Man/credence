defmodule Credence.Semantic.NoPipeIntoInExpression do
  @moduledoc """
  Repairs the compile-time error when piping into the `in` operator.

  LLMs frequently produce `expr |> fun() in collection` where `|>` has lower
  precedence than `in`, causing the compiler to parse it as
  `expr |> (fun() in collection)` and emit:

      the :in operator can only take two arguments

  The fix wraps the piped expression in parentheses so `in` sees exactly two
  arguments:

      (expr |> fun()) in collection

  Semantics are identical — the parenthesised pipe produces the same value,
  and `in` still checks membership in the same collection.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "the :in operator can only take two arguments"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_pipe_into_in_expression,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    source
    |> String.split("\n")
    |> Enum.map_join("\n", &rewrite_line/1)
  end

  # Match `<expr> |> ...() in <collection>` and wrap the piped expression in
  # parens.  `(\s*)` captures leading whitespace outside the parens; the first
  # `.*?` (non-greedy) reaches the first `|>`; the second `.*` (greedy)
  # backtracks to the LAST `)` before ` in`, so chained pipes and function
  # calls with arguments are handled correctly.
  defp rewrite_line(line) do
    Regex.replace(~r/(\s*)(.*?\|>.*\))\s+in\b/, line, "\\1(\\2) in")
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
