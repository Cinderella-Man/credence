defmodule Credence.Pattern.NoListDeleteAtWithLength do
  @moduledoc """
  Detects `List.delete_at(list, length(list) - K)` where `length/1` is
  computed inline to build an index for `List.delete_at/2`.

  ## Why this matters

  `length/1` is O(n) and `List.delete_at/2` is also O(n), so the
  combination is O(2n).  An expert would use `Enum.split/2` to get
  both the last element and the prefix in a single O(n) pass:

      # Bad — two traversals
      last = List.last(tail)
      middle = List.delete_at(tail, length(tail) - 1)

      # Good — one traversal
      {middle, [last]} = Enum.split(tail, -1)

  When the intent is simply to drop the last element without needing
  it, `Enum.drop(tail, -1)` is also a single-pass alternative.

  ## Detection scope

  Matches `List.delete_at(x, length(x) - K)` where `x` is the same
  variable in both positions and `K` is a positive integer literal.
  Does NOT match when the length is stored in a separate variable
  (that case may be handled by `no_length_based_indexing`).

  ## Bad

      List.delete_at(tail, length(tail) - 1)

      List.delete_at(items, length(items) - 2)

  ## Good

      {prefix, [_last]} = Enum.split(tail, -1)

      Enum.drop(items, -2)

  ## Auto-fix

  Check-only — the idiomatic replacement depends on whether the
  caller also needs the removed element(s).
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case match_delete_at_length(node) do
          {:ok, var_name, k, meta} ->
            {node, [build_issue(var_name, k, meta) | acc]}

          :error ->
            {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # Matches: List.delete_at(x, length(x) - K)
  #   where x is the same variable and K is a positive integer literal.
  defp match_delete_at_length(
         {{:., _, [{:__aliases__, _, [:List]}, :delete_at]}, meta,
          [list_arg, {:-, _, [length_call, k_arg]}]}
       ) do
    with {:ok, list_var} <- extract_var(list_arg),
         {:ok, length_var} <- extract_length_var(length_call),
         true <- list_var == length_var,
         {:ok, k} <- extract_pos_integer(k_arg) do
      {:ok, list_var, k, meta}
    else
      _ -> :error
    end
  end

  defp match_delete_at_length(_), do: :error

  defp extract_var({name, _, ctx}) when is_atom(name) and is_atom(ctx) and name != :_,
    do: {:ok, name}

  defp extract_var(_), do: :error

  defp extract_length_var({:length, _, [arg]}), do: extract_var(arg)

  defp extract_length_var({{:., _, [{:__aliases__, _, [:Kernel]}, :length]}, _, [arg]}),
    do: extract_var(arg)

  defp extract_length_var(_), do: :error

  defp extract_pos_integer({:__block__, _, [k]}) when is_integer(k) and k > 0, do: {:ok, k}
  defp extract_pos_integer(k) when is_integer(k) and k > 0, do: {:ok, k}
  defp extract_pos_integer(_), do: :error

  defp build_issue(var_name, k, meta) do
    k_desc = if k == 1, do: "1", else: "#{k}"

    %Issue{
      rule: :no_list_delete_at_with_length,
      message:
        "`List.delete_at(#{var_name}, length(#{var_name}) - #{k_desc})` traverses the list " <>
          "twice (once for `length/1`, once for `delete_at/2`). " <>
          "Use `Enum.split(#{var_name}, -#{k_desc})` to get both parts in a single pass, " <>
          "or `Enum.drop(#{var_name}, -#{k_desc})` if you only need the shortened list.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
