defmodule Credence.Rule.NoDocFalseOnPrivate do
  @moduledoc """
  Style rule: Detects `@doc false` placed before private functions (`defp`).

  Private functions cannot have documentation — the compiler ignores `@doc`
  on `defp` entirely. Adding `@doc false` is redundant noise that misleads
  readers into thinking it's suppressing something.

  ## Bad

      @doc false
      defp helper(x), do: x + 1

  ## Good

      defp helper(x), do: x + 1

      # If you want to hide a public function from docs:
      @doc false
      def internal_api(x), do: x + 1
  """

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

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
                if doc_false_node?(doc_node) and defp_node?(defp_node),
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
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.prewalk(fn
      {:__block__, meta, stmts} when is_list(stmts) ->
        {:__block__, meta, drop_redundant_doc_false(stmts)}

      node ->
        node
    end)
    |> Sourceror.to_string()
  end

  # --- Shared helpers (both AST shapes) ---

  # Matches @doc false in both standard AST and Sourceror AST.
  # Sourceror wraps literals in __block__, so `false` becomes
  # {:__block__, meta, [false]}.
  defp doc_false_node?({:@, _, [{:doc, _, [false]}]}), do: true
  defp doc_false_node?({:@, _, [{:doc, _, [{:__block__, _, [false]}]}]}), do: true
  defp doc_false_node?(_), do: false

  # All defp forms (with or without guards) match {:defp, _, _}.
  defp defp_node?({:defp, _, _}), do: true
  defp defp_node?(_), do: false

  # --- Fix-specific: remove the offending nodes from statement lists ---

  defp drop_redundant_doc_false([]), do: []

  defp drop_redundant_doc_false([doc_node, defp_node | rest]) do
    if doc_false_node?(doc_node) and defp_node?(defp_node) do
      [defp_node | drop_redundant_doc_false(rest)]
    else
      [doc_node | drop_redundant_doc_false([defp_node | rest])]
    end
  end

  defp drop_redundant_doc_false([node | rest]) do
    [node | drop_redundant_doc_false(rest)]
  end

  # --- Check-specific ---

  defp build_issue(meta) do
    %Issue{
      rule: :no_doc_false_on_private,
      message:
        "`@doc false` before `defp` is redundant — private functions cannot have documentation. " <>
          "Remove the `@doc false` annotation.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
