defmodule Credence.Pattern.NoListDeleteAtLength do
  @moduledoc """
  Detects `List.delete_at(list, length(list) - K)` — computing the length
  of a list just to use it as an index for `List.delete_at/2`.

  ## Why this matters

  `length/1` is O(n) and `List.delete_at/2` is another O(n), so the
  combination is always O(2n).  Elixir offers better alternatives:

  - To drop the last element alongside extracting it, use
    `Enum.split(list, -1)` which returns `{init, [last]}` in a single pass.
  - To drop the last element when you don't need it, restructure with
    pattern matching or `Enum.slice(list, 0..-2//1)`.

  ## Bad

      middle = List.delete_at(tail, length(tail) - 1)

      List.delete_at(items, length(items) - 2)

  ## Good

      {middle, [_last]} = Enum.split(tail, -1)

  ## Detection scope

  Matches `List.delete_at(x, length(x) - K)` where `x` is the same
  variable in both positions and `K` is a positive integer literal.
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
          case {extract_var_name(list_arg), extract_length_arg(length_call),
                extract_integer(k_arg)} do
            {{:ok, var}, {:ok, length_var}, {:ok, k}}
            when var == length_var and is_integer(k) and k > 0 ->
              {node, [build_issue(var, k, meta) | issues]}

            _ ->
              {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

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

  defp build_issue(var, k, meta) do
    drop_desc = if k == 1, do: "last element", else: "last #{k} elements"

    %Issue{
      rule: :no_list_delete_at_length,
      message:
        "`List.delete_at(#{var}, length(#{var}) - #{k})` computes the " <>
          "length just to delete the #{drop_desc}. " <>
          "Use `Enum.split(#{var}, -#{k})` to get both parts in one pass, " <>
          "or restructure with pattern matching.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
