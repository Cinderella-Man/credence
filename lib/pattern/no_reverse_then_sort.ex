defmodule Credence.Pattern.NoReverseThenSort do
  @moduledoc """
  Redundancy rule: Detects `Enum.reverse/1` immediately followed by `Enum.sort/1,2`,
  where the reverse is pointless because `Enum.sort/1,2` produces the same result
  regardless of input order.

  ## Flagged patterns

      Enum.reverse(list) |> Enum.sort()
      list |> Enum.reverse() |> Enum.sort()
      Enum.sort(Enum.reverse(list))

  ## Fix

  Remove the `Enum.reverse/1` — `Enum.sort/1,2` already ignores input order.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipeline form: ... |> Enum.reverse() |> Enum.sort(...)
        {:|>, meta, [left, right]} = node, issues ->
          reverse_node = rightmost(left)

          if remote_call?(right, :Enum, :sort) and
               remote_call?(reverse_node, :Enum, :reverse) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        # Nested call form: Enum.sort(Enum.reverse(list))
        {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, meta,
         [{{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, _}]} = node,
        issues ->
          {node, [build_issue(meta) | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, fn
      # Pipeline: ... |> Enum.reverse() |> Enum.sort(...)
      {:|>, pipe_meta, [left, sort_node]} = node ->
        if remote_call?(sort_node, :Enum, :sort) do
          fix_pipeline(left, pipe_meta, sort_node, node)
        else
          node
        end

      # Nested: Enum.sort(Enum.reverse(list))
      {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, [reverse_node]} = node ->
        if remote_call?(reverse_node, :Enum, :reverse) do
          fix_nested(reverse_node, node)
        else
          node
        end

      node ->
        node
    end)
  end

  # Multi-step pipe: before |> Enum.reverse() |> Enum.sort(...)
  defp fix_pipeline({:|>, _, [before_reverse, reverse_node]}, pipe_meta, sort_node, fallback) do
    if remote_call?(reverse_node, :Enum, :reverse) do
      sort_args = call_args(sort_node)

      if sort_args == [] do
        {:|>, pipe_meta, [before_reverse, sort_node]}
      else
        {:|>, pipe_meta, [before_reverse, build_sort_call(sort_args)]}
      end
    else
      fallback
    end
  end

  # Direct call piped to sort: Enum.reverse(x) |> Enum.sort(...)
  defp fix_pipeline(reverse_node, _pipe_meta, sort_node, fallback) do
    if remote_call?(reverse_node, :Enum, :reverse) do
      reverse_args = call_args(reverse_node)

      if length(reverse_args) == 1 do
        subject = hd(reverse_args)
        sort_args = call_args(sort_node)

        if sort_args == [] do
          build_sort_call([subject])
        else
          build_sort_call([subject | sort_args])
        end
      else
        fallback
      end
    else
      fallback
    end
  end

  # Nested: Enum.sort(Enum.reverse(list)) → Enum.sort(list)
  defp fix_nested(reverse_node, fallback) do
    reverse_args = call_args(reverse_node)
    build_sort_call(reverse_args)
  rescue
    _ -> fallback
  end

  defp build_sort_call(args) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :sort]}, [], args}
  end

  defp call_args({{:., _, _}, _, args}), do: args
  defp call_args(_), do: []

  defp rightmost({:|>, _, [_, right]}), do: right
  defp rightmost(other), do: other

  defp remote_call?(node, mod, func) do
    match?({{:., _, [{:__aliases__, _, [^mod]}, ^func]}, _, _}, node)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_reverse_then_sort,
      message:
        "Avoid `Enum.reverse/1` before `Enum.sort/1,2`. " <>
          "Sorting ignores input order, so the reverse is a wasted O(n) pass.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
