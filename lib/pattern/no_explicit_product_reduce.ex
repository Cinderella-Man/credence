defmodule Credence.Pattern.NoExplicitProductReduce do
  @moduledoc """
  Flags explicit product-reduction patterns inside Enum.reduce/3.

  ## Bad

      defmodule BadCapture do
        def prod_value(list) do
          Enum.reduce(list, 1, &*/2)
        end
      end

  ## Good

      defmodule BadCapture do
        def prod_value(list) do
          Enum.product(list)
        end
      end
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def priority, do: 501

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., _, _}, meta, args} = node, issues ->
          if reduce_call?(node) and product_reduce_body?(args) do
            issue = %Issue{
              rule: :no_explicit_product_reduce,
              message: "Explicit product-reduction detected. Prefer Enum.product/1.",
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
        if reduce_call?(node) and product_reduce_body?(args) do
          [enum | _] = args
          enum_product_call(enum)
        else
          node
        end

      node ->
        node
    end)
  end

  defp enum_product_call(enum) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :product]}, [], [enum]}
  end

  defp reduce_call?({{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, _}), do: true
  defp reduce_call?({{:., _, [:Enum, :reduce]}, _, _}), do: true
  defp reduce_call?(_), do: false

  defp product_reduce_body?([
         _enum,
         {:__block__, _, [1]},
         {:fn, _, [{:->, _, [[{v1, _, c1}, {v2, _, c2}], body]}]}
       ])
       when is_atom(v1) and is_atom(v2) and is_atom(c1) and is_atom(c2) and v1 != v2 do
    explicit_product?(body, v1, v2)
  end

  # Capture syntax: Enum.reduce(enum, 1, &*/2)
  defp product_reduce_body?([
         _enum,
         {:__block__, _, [1]},
         {:&, _, [{:/, _, [{:*, _, _}, _arity]}]}
       ]),
       do: true

  defp product_reduce_body?(_), do: false

  defp explicit_product?({:__block__, _, [body]}, v1, v2), do: explicit_product?(body, v1, v2)

  defp explicit_product?({:*, _, [a, b]}, v1, v2) do
    case {var_name(a), var_name(b)} do
      {{:ok, op1}, {:ok, op2}} -> Enum.sort([op1, op2]) == Enum.sort([v1, v2])
      _ -> false
    end
  end

  defp explicit_product?(_, _, _), do: false

  # A plain variable reference is `{name, meta, context}` where context is an
  # atom (nil or a hygiene context). A call such as `x()` has a list of args in
  # that position, so it is excluded.
  defp var_name({name, _, context}) when is_atom(name) and is_atom(context), do: {:ok, name}
  defp var_name(_), do: :error
end
