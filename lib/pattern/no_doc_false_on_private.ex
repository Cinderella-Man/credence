defmodule Credence.Pattern.NoDocFalseOnPrivate do
  @moduledoc """
  Style rule: Detects any `@doc` annotation placed before private functions (`defp`).

  Private functions cannot have documentation — the compiler ignores `@doc`
  on `defp` entirely. Adding `@doc` (whether `false` or a string) is redundant
  noise that misleads readers into thinking it's suppressing or providing docs.

  ## Bad

      defmodule HelpersNDFOP do
        @doc false
        defp helper(x), do: x + 1
      end

  ## Good

      defmodule HelpersNDFOP do
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
          {node, find_redundant_docs(stmts, acc)}

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

  defp spec_node?({:@, _, [{:spec, _, [_]}]}), do: true
  defp spec_node?(_), do: false

  defp redundant_private_doc?([doc_node | rest]) do
    doc_node?(doc_node) and private_function_follows?(rest)
  end

  defp private_function_follows?([{:defp, _, _} | _]), do: true
  defp private_function_follows?([spec_node, {:defp, _, _} | _]), do: spec_node?(spec_node)

  defp private_function_follows?(_), do: false

  defp find_redundant_docs([], found), do: found

  defp find_redundant_docs([doc_node | rest] = nodes, found) do
    if redundant_private_doc?(nodes) do
      find_redundant_docs(rest, [build_issue(elem(doc_node, 1)) | found])
    else
      find_redundant_docs(rest, found)
    end
  end

  defp drop_redundant_doc([]), do: []

  defp drop_redundant_doc([node | rest] = nodes) do
    if redundant_private_doc?(nodes) do
      drop_redundant_doc(rest)
    else
      [node | drop_redundant_doc(rest)]
    end
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
