defmodule Credence.Pattern.NoNestedEnumOnSameEnumerableUnfixable do
  @moduledoc """
  Detects nested `Enum.*` calls operating on the **same** enumerable
  where the inner call **cannot** be safely auto-fixed.

  Covers patterns such as:
  - `Enum.filter` inside `Enum.map` with a cross-referencing lambda parameter
  - `Enum.count` / `Enum.find` / `Enum.any?` / … inside a traversal

  These require manual restructuring (e.g. precomputation, a single
  `Enum.reduce/3` pass, or a `MapSet`-based approach).
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @enum_funcs [
    :map,
    :filter,
    :reduce,
    :count,
    :any?,
    :all?,
    :find,
    :find_value,
    :member?
  ]

  @impl true
  def fixable?, do: false

  @impl true
  def check(ast, _opts) do
    # Desugar pipes so `x |> Enum.func(args)` becomes `Enum.func(x, args)`.
    # This lets the direct-call extractor see the enumerable as the first arg.
    desugared = desugar_pipes(ast)

    {_ast, {_, issues}} =
      Macro.prewalk(desugared, {[], []}, fn node, {stack, issues} ->
        case extract_enum_call(node) do
          {:ok, func, var, meta} ->
            new_issues =
              if Enum.any?(stack, fn {_f, v} -> v == var end) do
                [
                  %Issue{
                    rule: :no_nested_enum_on_same_enumerable_unfixable,
                    message: build_message(func, var),
                    meta: %{line: Keyword.get(meta, :line)}
                  }
                ]
              else
                []
              end

            {node, {[{func, var} | stack], issues ++ new_issues}}

          _ ->
            {node, {stack, issues}}
        end
      end)

    issues
  end

  # Transforms `x |> f(a, b)` into `f(x, a, b)` so the piped-in value
  # appears as the first argument, matching the direct-call pattern.
  defp desugar_pipes(ast) do
    Macro.prewalk(ast, fn
      {:|>, _, [left, {call, meta, args}]} when is_list(args) ->
        {call, meta, [left | args]}

      node ->
        node
    end)
  end

  defp build_message(:filter, var) do
    """
    Enum.filter/2 is nested inside another traversal of `#{var}`, causing O(n²) complexity.
    Avoid filtering the same list repeatedly. Consider:
    • Precomputing results once
    • Sorting and using indexed access
    • Combining logic into a single Enum.reduce/3 pass
    """
  end

  defp build_message(:member?, var) do
    """
    Enum.member?/2 is used inside a traversal of `#{var}`, resulting in O(n²) complexity.
    Convert the list to a MapSet for O(1) lookups:
        set = MapSet.new(#{var})
        Enum.map(#{var}, fn x -> MapSet.member?(set, ...) end)
    """
  end

  defp build_message(func, var) do
    """
    Nested Enum.#{func} call on `#{var}` detected.
    This results in O(n²) complexity due to repeated full traversals.
    Consider:
    • Precomputing reusable data outside the loop
    • Using a single Enum.reduce/3 pass
    • Avoiding repeated scans of the same list
    """
  end

  defp extract_enum_call({{:., _, [{:__aliases__, _, [:Enum]}, func]}, _meta, [arg | _]})
       when func in @enum_funcs do
    case var_name(arg) do
      nil -> :error
      var -> {:ok, func, var, []}
    end
  end

  defp extract_enum_call(_), do: :error

  defp var_name({name, _, context}) when is_atom(name) and is_atom(context), do: name
  defp var_name(_), do: nil
end
