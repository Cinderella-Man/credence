defmodule Credence.Semantic.FixHallucinatedMapPutArity do
  @moduledoc """
  Fixes the compile warning caused by LLM-hallucinated `Map.put` calls.

  Two hallucination patterns:

  1. **`Map.put/5+`** (Python-dict style multi-key construction):

      # Wrong (hallucinated):
      Map.put(%{}, :type, :missing_required, :path, [:a])

      # Correct (chained Map.put/3):
      Map.put(Map.put(%{}, :type, :missing_required), :path, [:a])

  2. **`Map.put/2`** with a map literal second argument:

      # Wrong (hallucinated):
      Map.put(state, %{status: :suspended, reason: "payment_failed"})

      # Correct (Map.merge/2):
      Map.merge(state, %{status: :suspended, reason: "payment_failed"})

  The compiler emits a warning because `Map.put/2` (and `/4`, `/5`, etc.) are
  undefined — only `Map.put/3` exists. The fix chains pairs into nested
  `Map.put/3` calls, or rewrites `Map.put/2` to `Map.merge/2`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_fun "Map.put/"
  @match_why "is undefined or private"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_fun) and String.contains?(msg, @match_why)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_hallucinated_map_put_arity,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          # Map.put/2 with a map literal second arg → Map.merge/2
          {{:., dot_meta, [{:__aliases__, alias_meta, [:Map]}, :put]}, call_meta,
           [base, {:%{}, _, _} = map_literal]},
          _acc ->
            {{{:., dot_meta, [{:__aliases__, alias_meta, [:Map]}, :merge]}, call_meta,
              [base, map_literal]}, true}

          # Map.put/5+ with odd arg count → chained Map.put/3
          {{:., dot_meta, [{:__aliases__, alias_meta, [:Map]}, :put]}, call_meta, args}, _acc
          when is_list(args) and length(args) > 3 and rem(length(args), 2) == 1 ->
            [map | rest] = args
            pairs = Enum.chunk_every(rest, 2)

            chained =
              Enum.reduce(pairs, map, fn [key, value], acc ->
                {{:., dot_meta, [{:__aliases__, alias_meta, [:Map]}, :put]}, call_meta,
                 [acc, key, value]}
              end)

            {chained, true}

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
