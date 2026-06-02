defmodule Credence.Pattern.NoManualListDeleteAt do
  @moduledoc """
  Detects `Enum.take(x, i) ++ Enum.drop(x, i + 1)` — a hand-rolled
  reimplementation of `List.delete_at(x, i)`.

  ## Why this matters

  When code needs to remove an element at a specific index from a list,
  `List.delete_at/2` expresses the intent directly. The manual version
  using `Enum.take/2` and `Enum.drop/2` concatenated with `++` is
  harder to read and obscures intent.

  ## Bad

      remaining = Enum.take(list, index) ++ Enum.drop(list, index + 1)

  ## Good

      remaining = List.delete_at(list, index)

  ## Detection scope

  Matches `Enum.take(x, i) ++ Enum.drop(x, i + 1)` where `x` is the
  same variable on both sides and `i` is the same variable on both sides.

  ## Auto-fix

  Replaces the expression with `List.delete_at(x, i)`.
  """

  use Credence.Pattern.Rule
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case match_pattern(node) do
          {:ok, list_var, index_var, meta} ->
            {node, [build_issue(list_var, index_var, meta) | acc]}

          :error ->
            {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)

    RuleHelpers.patches_from_ast_transform(ast, source, fn input ->
      Macro.prewalk(input, fn node ->
        case match_pattern(node) do
          {:ok, list_var, index_var, _meta} ->
            list_delete_at_call(list_var, index_var)

          :error ->
            node
        end
      end)
    end)
  end

  # Matches: Enum.take(x, i) ++ Enum.drop(x, i + 1)
  defp match_pattern(
         {:++, meta,
          [
            take_call,
            drop_call
          ]}
       ) do
    with {:ok, list1, index1} <- extract_enum_take(take_call),
         {:ok, list2, index2, offset} <- extract_enum_drop(drop_call),
         true <- offset == 1,
         true <- same_var?(list1, list2),
         true <- same_var?(index1, index2) do
      {:ok, list1, index1, meta}
    else
      _ -> :error
    end
  end

  defp match_pattern(_), do: :error

  # Extracts list and index from Enum.take(list, index)
  defp extract_enum_take(
         {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, _meta, [list_arg, index_arg]}
       ) do
    with {:ok, list_var} <- extract_var(list_arg),
         {:ok, index_var} <- extract_var(index_arg) do
      {:ok, list_var, index_var}
    else
      _ -> :error
    end
  end

  defp extract_enum_take(_), do: :error

  # Extracts list, index, and offset from Enum.drop(list, index + offset)
  # Handles both index + offset and offset + index (commutative +)
  defp extract_enum_drop(
         {{:., _, [{:__aliases__, _, [:Enum]}, :drop]}, _meta,
          [list_arg, {:+, _, [arg1, arg2]}]}
       ) do
    with {:ok, list_var} <- extract_var(list_arg) do
      # Try both orderings: (var + int) or (int + var)
      case {extract_var(arg1), extract_var(arg2), extract_integer(arg1), extract_integer(arg2)} do
        {{:ok, index_var}, _, _, {:ok, offset}} ->
          {:ok, list_var, index_var, offset}

        {_, {:ok, index_var}, {:ok, offset}, _} ->
          {:ok, list_var, index_var, offset}

        _ ->
          :error
      end
    else
      _ -> :error
    end
  end

  defp extract_enum_drop(_), do: :error

  defp extract_var({name, _, ctx}) when is_atom(name) and is_atom(ctx) and name != :_,
    do: {:ok, name}

  defp extract_var(_), do: :error

  defp extract_integer({:__block__, _, [n]}) when is_integer(n), do: {:ok, n}
  defp extract_integer(n) when is_integer(n), do: {:ok, n}
  defp extract_integer(_), do: :error

  defp same_var?(name, name), do: true
  defp same_var?(_, _), do: false

  defp list_delete_at_call(list_var, index_var) do
    {{:., [], [{:__aliases__, [], [:List]}, :delete_at]}, [],
     [{list_var, [], nil}, {index_var, [], nil}]}
  end

  defp build_issue(list_var, index_var, meta) do
    %Issue{
      rule: :no_manual_list_delete_at,
      message:
        "`Enum.take(#{list_var}, #{index_var}) ++ Enum.drop(#{list_var}, #{index_var} + 1)` " <>
          "is a manual reimplementation of `List.delete_at/2`. " <>
          "Use `List.delete_at(#{list_var}, #{index_var})` instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
