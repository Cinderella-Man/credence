defmodule Credence.Pattern.NoEnumSliceWithLength do
  @moduledoc """
  Readability rule: Detects `Enum.slice(enum, 0, length(enum) - K)` where
  the same variable appears in both the first argument and the `length/1` call.

  Computing `length/1` just to pass it as the count argument to `Enum.slice/3`
  is redundant — Elixir's range-based `Enum.slice/2` form handles this
  natively without the extra traversal.

  ## Bad

      Enum.slice(list, 0, length(list) - 1)

      Enum.slice(items, 0, length(items) - 2)

  ## Good

      Enum.slice(list, 0..-2//1)

      Enum.slice(items, 0..-3//1)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:Enum]}, :slice]}, meta,
         [enum_arg, start_arg, {:-, _, [length_call, k_arg]}]} = node,
        issues ->
          case {extract_var_name(enum_arg), is_zero_literal(start_arg),
                extract_length_arg(length_call), extract_integer(k_arg)} do
            {{:ok, var}, true, {:ok, length_var}, {:ok, k}}
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
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, fn
      {{:., _, [{:__aliases__, _, [:Enum]}, :slice]}, _meta,
       [enum_arg, start_arg, {:-, _, [length_call, k_arg]}]} = node ->
        case {extract_var_name(enum_arg), is_zero_literal(start_arg),
              extract_length_arg(length_call), extract_integer(k_arg)} do
          {{:ok, var}, true, {:ok, length_var}, {:ok, k}}
          when var == length_var and is_integer(k) and k > 0 ->
            build_range_slice(enum_arg, k)

          _ ->
            node
        end

      node ->
        node
    end)
  end

  # Enum.slice(enum, 0..-(k+1)//1)
  defp build_range_slice(enum_arg, k) do
    range = {:..//, [], [0, -(k + 1), 1]}

    {{:., [], [{:__aliases__, [], [:Enum]}, :slice]}, [], [enum_arg, range]}
  end

  defp is_zero_literal(0), do: true
  defp is_zero_literal({:__block__, _, [0]}), do: true
  defp is_zero_literal(_), do: false

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
    %Issue{
      rule: :no_enum_slice_with_length,
      message:
        "`Enum.slice(#{var}, 0, length(#{var}) - #{k})` computes `length/1` " <>
          "just to use it as a count. " <>
          "Use `Enum.slice(#{var}, 0..-#{k + 1}//1)` instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
