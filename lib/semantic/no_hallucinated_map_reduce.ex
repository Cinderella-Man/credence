defmodule Credence.Semantic.NoHallucinatedMapReduce do
  @moduledoc """
  Fixes the compile error caused by calling `Map.reduce/3`.

  `Map.reduce/3` does not exist in Elixir — it is a common LLM hallucination.
  The compiler emits:

      "Map.reduce/3 is undefined or private"

  The deterministic fix replaces `Map.reduce/3` with `Enum.reduce/3` and
  restructures the anonymous function callback from
  `fn key, value, acc -> ...` to `fn {key, value}, acc -> ...`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_target "Map.reduce/"

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
      rule: :no_hallucinated_map_reduce,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          # Match Map.reduce(enumerable, initial, fn arg1, arg2, arg3 -> body end)
          {{:., dot_meta, [{:__aliases__, alias_meta, [:Map]}, :reduce]}, call_meta,
           [
             enumerable,
             initial,
             {:fn, fn_meta, [{:->, arrow_meta, [[arg1, arg2, arg3], body]}]}
           ]},
          _acc ->
            # Change Map -> Enum
            new_alias = {:__aliases__, alias_meta, [:Enum]}
            # Transform first two args into a tuple pattern
            tuple_pattern = {:__block__, [line: fn_meta[:line]], [{arg1, arg2}]}
            new_fn = {:fn, fn_meta, [{:->, arrow_meta, [[tuple_pattern, arg3], body]}]}

            new_call =
              {{:., dot_meta, [new_alias, :reduce]}, call_meta,
               [enumerable, initial, new_fn]}

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
