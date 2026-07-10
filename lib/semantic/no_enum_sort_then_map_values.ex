defmodule Credence.Semantic.NoEnumSortThenMapValues do
  @moduledoc """
  Fixes `Map.values/1` calls piped after `Enum.sort_by/2`.

  `Enum.sort_by/2` on a map returns a sorted list of `{key, value}` tuples,
  not a map. Piping that into `Map.values/1` raises `BadMapError` on every
  input because a list is not a map.

  The fix replaces `|> Map.values()` with `|> Enum.map(fn {_, v} -> v end)`,
  which correctly extracts values from the sorted tuple list.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "the result of evaluating operator '+'/2 is ignored"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_enum_sort_then_map_values,
      message:
        "Piping Enum.sort_by/2 into Map.values/1 raises BadMapError; use Enum.map(fn {_, v} -> v end) to extract values",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          # Match: ... |> Map.values()  (pipe with Map.values/0 on the right)
          {:|>, pipe_meta,
           [
             left,
             {{:., dot_meta, [{:__aliases__, alias_meta, [:Map]}, :values]}, call_meta, []}
           ]},
          acc ->
            if contains_sort_by?(left) do
              # Build: Enum.map(fn {_, v} -> v end)
              new_fn =
                {:fn, [],
                 [
                   {:->, [],
                    [
                      [{:__block__, [], [{{:_, [], nil}, {:v, [], nil}}]}],
                      {:v, [], nil}
                    ]}
                 ]}

              new_right =
                {{:., dot_meta, [{:__aliases__, [], [:Enum]}, :map]}, call_meta, [new_fn]}

              {{:|>, pipe_meta, [left, new_right]}, true}
            else
              # Not after sort_by — leave unchanged
              original =
                {:|>, pipe_meta,
                 [
                   left,
                   {{:., dot_meta, [{:__aliases__, alias_meta, [:Map]}, :values]}, call_meta, []}
                 ]}

              {original, acc}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # Returns true if the AST subtree contains an Enum.sort_by/2 call.
  defp contains_sort_by?(ast) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {{:., _, [{:__aliases__, _, [:Enum]}, :sort_by]}, _, _} = node, _acc ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
