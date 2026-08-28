defmodule Credence.Pattern.PreferEnumReverseTwo do
  @moduledoc """
  Performance rule: Flags `Enum.reverse(list) ++ other_list`.
  `Enum.reverse/1` creates a new list, and `++` traverses that new list
  entirely to append the second. This is a 2-pass operation.
  Using `Enum.reverse/2` performs both actions in a single optimized pass.
  ## Bad
      defp do_merge([], l2, acc), do: Enum.reverse(acc) ++ l2
  ## Good
      defp do_merge([], l2, acc), do: Enum.reverse(acc, l2)
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    if enum_aliased?(ast) do
      []
    else
      {_ast, issues} =
        Macro.prewalk(ast, [], fn node, issues ->
          case rewrite(node) do
            {:ok, _replacement, meta} -> {node, [create_issue(meta) | issues]}
            :error -> {node, issues}
          end
        end)

      Enum.reverse(issues)
    end
  end

  @impl true
  def fix_patches(ast, _opts) do
    if enum_aliased?(ast) do
      []
    else
      Credence.RuleHelpers.patches_from_postwalk(ast, fn node ->
        case rewrite(node) do
          {:ok, replacement, _meta} -> replacement
          :error -> node
        end
      end)
    end
  end

  defp rewrite({:++, meta, [{{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, [acc]}, tail]}) do
    if safe_tail?(tail) do
      {:ok, {{:., [], [{:__aliases__, [], [:Enum]}, :reverse]}, [], [acc, tail]}, meta}
    else
      :error
    end
  end

  defp rewrite(_node), do: :error

  # Moving the second argument before reverse/1 is observable when evaluating it
  # can have effects or raise. Variables and literal data are safe to move.
  defp safe_tail?({name, _meta, context})
       when is_atom(name) and (is_atom(context) or is_nil(context)),
       do: true

  defp safe_tail?(value) when is_atom(value) or is_number(value) or is_binary(value), do: true
  defp safe_tail?(values) when is_list(values), do: Enum.all?(values, &safe_tail?/1)
  defp safe_tail?({:{}, _meta, values}), do: Enum.all?(values, &safe_tail?/1)

  defp safe_tail?({:%{}, _meta, pairs}) do
    Enum.all?(pairs, fn {key, value} -> safe_tail?(key) and safe_tail?(value) end)
  end

  defp safe_tail?(_node), do: false

  defp enum_aliased?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {:alias, _, [_, opts]} = node, found? when is_list(opts) ->
          as_enum? =
            Enum.any?(opts, fn
              {{:__block__, _, [:as]}, {:__aliases__, _, [:Enum]}} -> true
              {:as, {:__aliases__, _, [:Enum]}} -> true
              _ -> false
            end)

          {node, found? or as_enum?}

        node, found? ->
          {node, found?}
      end)

    found?
  end

  defp create_issue(meta) do
    %Issue{
      rule: :prefer_enum_reverse_two,
      message:
        "Pattern to avoid:\n" <>
          "  Enum.reverse(list1) ++ list2\n\n" <>
          "Use instead:\n" <>
          "  Enum.reverse(list1, list2)\n\n" <>
          "This applies regardless of variable names.\n\n" <>
          "Reason:\n" <>
          "- Enum.reverse(list1) creates a new reversed list.\n" <>
          "- The ++ operator then traverses that entire list again to append list2.\n" <>
          "- This causes two full traversals.\n\n" <>
          "Enum.reverse(list1, list2) performs the same operation in a single pass,\n" <>
          "which is more efficient in both time and memory.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
