defmodule Credence.Pattern.NoDocFalseOnPrivate do
  @moduledoc """
  Style rule: Detects any `@doc` attribute placed before private functions (`defp`).

  Private functions cannot have documentation — the compiler ignores `@doc`
  on `defp` entirely and warns about it (which becomes an error under
  `--warnings-as-errors`). This catches both `@doc false` (redundant noise)
  and `@doc` with actual content (dead code that will never appear in docs).

  Intermediate `@spec` or `@impl` attributes between `@doc` and `defp`
  are tolerated — the `@doc` is still flagged.

  ## Bad

      @doc false
      defp helper(x), do: x + 1

      @doc "Calculates something"
      defp compute(x), do: x + 1

      @spec process(integer()) :: integer()
      defp process(x), do: x + 1

  ## Good

      defp helper(x), do: x + 1

      # If you want to hide a public function from docs:
      @doc false
      def internal_api(x), do: x + 1
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:__block__, _, stmts} = node, acc when is_list(stmts) ->
          new_issues = find_doc_on_private(stmts, acc)
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

  # Walk block statements tracking a pending @doc index.
  # When @doc is followed (possibly through @spec/@impl/etc.) by defp,
  # flag the issue. Any non-attribute, non-defp node clears the pending doc.
  defp find_doc_on_private(stmts, acc) do
    Enum.with_index(stmts)
    |> Enum.reduce({acc, nil}, fn
      {node, _idx}, {issues, pending} ->
        cond do
          doc_attr?(node) ->
            {issues, node}

          other_attr?(node) ->
            {issues, pending}

          match?({:defp, _, _}, node) and pending != nil ->
            {[build_issue(elem(pending, 1)) | issues], nil}

          true ->
            {issues, nil}
        end
    end)
    |> elem(0)
  end

  # Drop @doc nodes that are followed (possibly through @spec/@impl) by defp.
  # Uses index-based removal to preserve statement order.
  defp drop_redundant_doc(stmts) do
    indices_to_remove = doc_indices_for_defp(stmts)

    if indices_to_remove == [] do
      stmts
    else
      remove_set = MapSet.new(indices_to_remove)

      stmts
      |> Enum.with_index()
      |> Enum.reject(fn {_node, idx} -> MapSet.member?(remove_set, idx) end)
      |> Enum.map(fn {node, _idx} -> node end)
    end
  end

  # Find indices of @doc nodes that are followed by defp (through @-attrs).
  defp doc_indices_for_defp(stmts) do
    Enum.with_index(stmts)
    |> Enum.reduce({nil, []}, fn
      {node, idx}, {pending_idx, indices} ->
        cond do
          doc_attr?(node) ->
            {idx, indices}

          other_attr?(node) ->
            {pending_idx, indices}

          match?({:defp, _, _}, node) and pending_idx != nil ->
            {nil, [pending_idx | indices]}

          true ->
            {nil, indices}
        end
    end)
    |> elem(1)
  end

  defp doc_attr?({:@, _, [{:doc, _, _}]}), do: true
  defp doc_attr?(_), do: false

  defp other_attr?({:@, _, _}), do: true
  defp other_attr?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :no_doc_false_on_private,
      message:
        "`@doc` before `defp` is discarded by the compiler — private functions cannot have documentation. " <>
          "Remove the `@doc` annotation.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
