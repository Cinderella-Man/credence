defmodule Credence.Semantic.NoDeprecatedNotIn do
  @moduledoc """
  Repairs the deprecation warning for `not expr1 in expr2`.

  Elixir 1.18+ deprecates `not x in y` (which parses as `not (x in y)`)
  in favour of the idiomatic `x not in y`.  Under `--warnings-as-errors`
  this becomes a compile failure.  The compiler emits:

      "not expr1 in expr2" is deprecated, use "expr1 not in expr2" instead

  The fix is a deterministic source-level rewrite on the flagged line:
  replace `not <expr> in <expr>` with `<expr> not in <expr>`.
  Semantics are identical — `not (x in y)` and `x not in y` are the same
  boolean — so the behaviour is preserved.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "\"not expr1 in expr2\" is deprecated, use \"expr1 not in expr2\" instead"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    msg == @match_msg
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_deprecated_not_in,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{position: {line_no, _col}}) when is_integer(line_no) do
    rewrite_line(source, line_no)
  end

  def fix(source, %{position: line_no}) when is_integer(line_no) do
    rewrite_line(source, line_no)
  end

  def fix(source, _diagnostic), do: source

  defp rewrite_line(source, line_no) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn
      {text, ^line_no} -> rewrite_not_in(text)
      {text, _} -> text
    end)
  end

  # Replace `not <expr> in <expr>` with `<expr> not in <expr>`.
  # `\bnot\s+` anchors to the `not` keyword; `.+?` captures the
  # shortest expression before `\s+in\b`.
  defp rewrite_not_in(text) do
    Regex.replace(~r/\bnot\s+(.+?)\s+in\b/, text, "\\1 not in")
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
