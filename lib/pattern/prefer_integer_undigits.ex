defmodule Credence.Pattern.PreferIntegerUndigits do
  @moduledoc """
  Detects manual digit-to-integer conversion via `Enum.reduce/3` and rewrites
  to `Integer.undigits/1`.

  The classic `Enum.reduce(digits, 0, fn d, acc -> acc * 10 + d end)` pattern
  reimplements `Integer.undigits/1` with no benefit:

  ## Bad

      Enum.reduce(digits, 0, fn digit, acc ->
        acc * 10 + digit
      end)

  ## Good

      Integer.undigits(digits)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., _, _}, meta, args} = node, issues ->
          if reduce_call?(node) and undigits_reduce_body?(args) do
            issue = %Issue{
              rule: :prefer_integer_undigits,
              message: "Manual digit-to-integer conversion detected. Prefer Integer.undigits/1.",
              meta: %{line: Keyword.get(meta, :line)}
            }

            {node, [issue | issues]}
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
      {{:., _, _}, _, args} = node ->
        if reduce_call?(node) and undigits_reduce_body?(args) do
          [enum | _] = args
          integer_undigits_call(enum)
        else
          node
        end

      node ->
        node
    end)
  end

  defp integer_undigits_call(enum) do
    {{:., [], [{:__aliases__, [], [:Integer]}, :undigits]}, [], [enum]}
  end

  defp reduce_call?({{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, _}), do: true
  defp reduce_call?({{:., _, [:Enum, :reduce]}, _, _}), do: true
  defp reduce_call?(_), do: false

  # Match: Enum.reduce(enum, 0, fn elem, acc -> ... end)
  # where elem != acc (distinct param names)
  defp undigits_reduce_body?([
         _enum,
         {:__block__, _, [0]},
         {:fn, _, [{:->, _, [[{v1, _, c1}, {v2, _, c2}], body]}]}
       ])
       when is_atom(v1) and is_atom(v2) and is_atom(c1) and is_atom(c2) and v1 != v2 do
    undigits_body?(body, v1, v2)
  end

  defp undigits_reduce_body?(_), do: false

  # Unwrap single-expression block wrapper
  defp undigits_body?({:__block__, _, [body]}, v1, v2), do: undigits_body?(body, v1, v2)

  # acc * 10 + elem
  defp undigits_body?(
         {:+, _, [{:*, _, [{acc_name, _, _}, {:__block__, _, [10]}]}, {elem_name, _, _}]},
         v1,
         v2
       )
       when is_atom(acc_name) and is_atom(elem_name) do
    acc_name == v2 and elem_name == v1
  end

  # elem + acc * 10 (commutative addition)
  defp undigits_body?(
         {:+, _, [{elem_name, _, _}, {:*, _, [{acc_name, _, _}, {:__block__, _, [10]}]}]},
         v1,
         v2
       )
       when is_atom(acc_name) and is_atom(elem_name) do
    acc_name == v2 and elem_name == v1
  end

  defp undigits_body?(_, _, _), do: false
end
