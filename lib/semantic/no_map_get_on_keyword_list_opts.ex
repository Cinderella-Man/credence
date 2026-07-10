defmodule Credence.Semantic.NoMapGetOnKeywordListOpts do
  @moduledoc """
  Repairs `Map.get/2` calls on keyword-list `opts` to use `Keyword.get/2`.

  LLMs commonly write `Map.get(opts, :key)` when `opts` is a keyword list
  (e.g. `def f(opts \\ [])`), which causes `BadMapError` at runtime since
  keyword lists are lists of `{key, value}` tuples, not maps. The idiomatic
  API for keyword list lookup is `Keyword.get/2`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "Map.get/2 called on keyword list opts"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_map_get_on_keyword_list_opts,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {{:., dot_meta, [{:__aliases__, alias_meta, [:Map]}, :get]}, call_meta, args}, _acc ->
            new_node =
              {{:., dot_meta, [{:__aliases__, alias_meta, [:Keyword]}, :get]}, call_meta, args}

            {new_node, true}

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
