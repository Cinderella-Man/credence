defmodule Credence.Semantic.FixHallucinatedEnumRange do
  @moduledoc """
  Fixes the compile warning caused by calling `Enum.range/2`.

  `Enum.range/2` does not exist in Elixir — it is a common LLM hallucination.
  The compiler emits:

      "Enum.range/2 is undefined or private"

  The fix replaces `Enum.range(a, b)` with the idiomatic range literal `a..b`.
  When the second argument is a compound expression (e.g. `length(list) - 1`),
  Sourceror automatically adds parentheses to preserve operator precedence.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_target "Enum.range/"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_target) and
      (String.contains?(msg, "undefined or private") or
         String.contains?(msg, "undefined function"))
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_hallucinated_enum_range,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {{:., _dot_meta, [{:__aliases__, _alias_meta, [:Enum]}, :range]}, _call_meta,
           [first, last]},
          _acc ->
            {{:.., [], [first, last]}, true}

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
