defmodule Credence.Semantic.NoStreamDataTupleWithList do
  @moduledoc """
  Repairs calls to `StreamData.tuple/1` where the argument is a list (`[]`)
  instead of a tuple (`{}`).

  `StreamData.tuple/1` requires a tuple of generators — passing a list causes
  a `FunctionClauseError` at runtime:

      ** (FunctionClauseError) no function clause matching in StreamData.tuple/1

  The fix wraps the list elements as a tuple: `StreamData.tuple({gen1, gen2})`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "no function clause matching in StreamData.tuple"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_stream_data_tuple_with_list,
      message: "StreamData.tuple/1 expects a tuple of generators, not a list — use {gen1, gen2}",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {new_ast, changed} =
          Macro.prewalk(ast, false, fn
            # Qualified: StreamData.tuple([a, b])
            {{:., dot_meta, [{:__aliases__, alias_meta, [:StreamData]}, :tuple]}, call_meta,
             [{:__block__, block_meta, [list]}]},
            _acc when is_list(list) ->
              new_node =
                {{:., dot_meta, [{:__aliases__, alias_meta, [:StreamData]}, :tuple]}, call_meta,
                 [{:__block__, block_meta, [List.to_tuple(list)]}]}

              {new_node, true}

            # Imported: tuple([a, b])
            {:tuple, tuple_meta, [{:__block__, block_meta, [list]}]}, _acc
            when is_list(list) ->
              new_node = {:tuple, tuple_meta, [{:__block__, block_meta, [List.to_tuple(list)]}]}
              {new_node, true}

            node, acc ->
              {node, acc}
          end)

        if changed, do: Sourceror.to_string(new_ast), else: source

      _ ->
        source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
