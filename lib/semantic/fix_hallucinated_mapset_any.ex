defmodule Credence.Semantic.FixHallucinatedMapsetAny do
  @moduledoc """
  Fixes the compile error caused by calling `MapSet.any?/2`.

  `MapSet.any?/2` does not exist in Elixir — it is a common LLM hallucination.
  The compiler emits:

      "MapSet.any?/2 is undefined or private"

  The deterministic fix replaces `MapSet.any?/2` with `Enum.any?/2`.  Both
  accept MapSets (MapSet implements `Enumerable`), so the semantics are
  preserved.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_target "MapSet.any?"

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
      rule: :fix_hallucinated_mapset_any,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {{:., dot_meta,
            [
              {:__aliases__, alias_meta, [:MapSet]},
              :any?
            ]}, call_meta, args},
          _acc ->
            new_alias = {:__aliases__, alias_meta, [:Enum]}

            new_call =
              {{:., dot_meta, [new_alias, :any?]}, call_meta, args}

            {new_call, true}

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
