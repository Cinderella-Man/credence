defmodule Credence.Pattern.NoDocFalseOnPrivate do
  @moduledoc """
  Style rule: Detects any `@doc` annotation placed before private functions (`defp`).

  Private functions cannot have documentation — the compiler ignores `@doc`
  on `defp` entirely. Adding `@doc` (whether `false` or a string) is redundant
  noise that misleads readers into thinking it's suppressing or providing docs.

  ## Bad

      defmodule Helpers do
        @doc false
        defp helper(x), do: x + 1
      end

  ## Good

      defmodule Helpers do
        defp helper(x), do: x + 1
      end
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:__block__, _, stmts} = node, acc when is_list(stmts) ->
          new_issues =
            stmts
            |> Enum.chunk_every(2, 1, :discard)
            |> Enum.reduce(acc, fn
              [doc_node, defp_node], found ->
                if doc_node?(doc_node) and defp_node?(defp_node),
                  do: [build_issue(elem(doc_node, 1)) | found],
                  else: found

              _, found ->
                found
            end)

          {node, new_issues}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {:__block__, meta, stmts} when is_list(stmts) ->
        {:__block__, meta, drop_redundant_doc(stmts)}

      node ->
        node
    end)
  end

  # Matches any @doc annotation (including @doc false, @doc "...", @doc """...""").
  # Sourceror wraps literals in __block__, so `false` becomes
  # {:__block__, meta, [false]} and strings become {:__block__, meta, ["..."]}.
  defp doc_node?({:@, _, [{:doc, _, [_]}]}), do: true
  defp doc_node?(_), do: false

  # All defp forms (with or without guards) match {:defp, _, _}.
  defp defp_node?({:defp, _, _}), do: true
  defp defp_node?(_), do: false
  defp drop_redundant_doc([]), do: []

  defp drop_redundant_doc([doc_node, defp_node | rest]) do
    if doc_node?(doc_node) and defp_node?(defp_node) do
      [defp_node | drop_redundant_doc(rest)]
    else
      [doc_node | drop_redundant_doc([defp_node | rest])]
    end
  end

  defp drop_redundant_doc([node | rest]) do
    [node | drop_redundant_doc(rest)]
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_doc_false_on_private,
      message:
        "`@doc` before `defp` is redundant — private functions cannot have documentation. " <>
          "Remove the `@doc` annotation.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
