defmodule Credence.Pattern.NoListDeleteAtLength do
  @moduledoc """
  Detects `List.delete_at(list, length(list) - 1)` — computing the length
  of a list just to index its last element for deletion.

  ## Why this matters

  `length/1` is O(n) and `List.delete_at/2` is another O(n), so the
  combination walks the list twice. `List.delete_at/2` already accepts
  negative indexes counted from the end, so `List.delete_at(list, -1)`
  deletes the last element in a single pass — the length call is pure
  overhead.

  ## Bad

      middle = List.delete_at(tail, length(tail) - 1)

  ## Good

      middle = List.delete_at(tail, -1)

  ## Detection scope

  Matches `List.delete_at(x, length(x) - 1)` where `x` is the **same
  variable** in both positions and the subtracted literal is exactly `1`.

  Larger offsets such as `List.delete_at(x, length(x) - 2)` are **not**
  flagged: `length(x) - K` differs from `-K` for short lists (when
  `length(x) < K` the left form yields a negative index that still
  deletes an element from the end, while `-K` is out of range and deletes
  nothing), so no constant-index rewrite is behaviour-preserving for them.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:List]}, :delete_at]}, meta,
         [list_arg, {:-, _, [length_call, k_arg]}]} = node,
        issues ->
          if delete_last?(list_arg, length_call, k_arg) do
            {node, [build_issue(extract_var_name!(list_arg), meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {{:., _, [{:__aliases__, _, [:List]}, :delete_at]}, meta,
       [list_arg, {:-, _, [length_call, k_arg]}]} = node ->
        if delete_last?(list_arg, length_call, k_arg) do
          {{:., meta, [{:__aliases__, [], [:List]}, :delete_at]}, meta, [list_arg, {:-, [], [1]}]}
        else
          node
        end

      node ->
        node
    end)
  end

  # Fires only when the index is `length(x) - 1` with `x` the same plain
  # variable in both `List.delete_at` and `length`, i.e. "delete the last
  # element". This is the one offset where `length(x) - K` is provably
  # equal to the constant `-K` for every list (including empty/short ones)
  # and raises identically on non-lists.
  defp delete_last?(list_arg, length_call, k_arg) do
    with {:ok, var} <- extract_var_name(list_arg),
         {:ok, length_var} <- extract_length_arg(length_call),
         {:ok, 1} <- extract_integer(k_arg) do
      var == length_var
    else
      _ -> false
    end
  end

  defp extract_var_name!(arg) do
    {:ok, name} = extract_var_name(arg)
    name
  end

  defp extract_var_name({name, _, ctx}) when is_atom(name) and is_atom(ctx) and name != :_,
    do: {:ok, name}

  defp extract_var_name(_), do: :error

  defp extract_length_arg({:length, _, [arg]}), do: extract_var_name(arg)

  defp extract_length_arg({{:., _, [{:__aliases__, _, [:Kernel]}, :length]}, _, [arg]}),
    do: extract_var_name(arg)

  defp extract_length_arg(_), do: :error

  defp extract_integer({:__block__, _, [n]}) when is_integer(n), do: {:ok, n}
  defp extract_integer(n) when is_integer(n), do: {:ok, n}
  defp extract_integer(_), do: :error

  defp build_issue(var, meta) do
    %Issue{
      rule: :no_list_delete_at_length,
      message:
        "`List.delete_at(#{var}, length(#{var}) - 1)` computes the " <>
          "length just to delete the last element. " <>
          "Use `List.delete_at(#{var}, -1)` to delete it in one pass.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
