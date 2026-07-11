defmodule Credence.Semantic.FixHallucinatedMapUpdateArity do
  @moduledoc """
  Fixes the compile warning caused by LLM-hallucinated `Map.update/3` calls.

  LLMs frequently hallucinate `Map.update/3` (missing the default argument):

      # Wrong (hallucinated):
      Map.update(map, key, fn val -> val + 1 end)

      # Correct (Map.update/4 with default 0):
      Map.update(map, key, 0, fn val -> val + 1 end)

  The compiler emits a warning because `Map.update/3` is undefined — only
  `Map.update/4` exists. The fix inserts `0` as the missing default argument.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_fun "Map.update/"
  @match_why "is undefined or private"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_fun) and String.contains?(msg, @match_why)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_hallucinated_map_update_arity,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {{:., dot_meta, [{:__aliases__, alias_meta, [:Map]}, :update]}, call_meta, args},
          _acc
          when is_list(args) and length(args) == 3 ->
            [map, key, fun] = args
            zero = {:__block__, [token: "0"], [0]}

            new_call =
              {{:., dot_meta, [{:__aliases__, alias_meta, [:Map]}, :update]}, call_meta,
               [map, key, zero, fun]}

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
