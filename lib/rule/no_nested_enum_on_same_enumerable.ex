defmodule Credence.Rule.NoNestedEnumOnSameEnumerable do
  @behaviour Credence.Rule
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
  def check(ast, _opts) do
    {_ast, {_, issues}} =
      Macro.prewalk(ast, {[], []}, fn node, {stack, issues} ->
        case extract_enum_call(node) do
          {:ok, func, var, meta} ->
            new_issues =
              if Enum.any?(stack, fn {_f, v} -> v == var end) do
                [
                  %Issue{
                    rule: :no_nested_enum_on_same_enumerable,
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

  # --- Pattern-aware messaging ---

  defp build_message(:member?, var) do
    """
    Enum.member?/2 is used inside a traversal of `#{var}`, resulting in O(n²) complexity.

    Convert the list to a MapSet for O(1) lookups:

        set = MapSet.new(#{var})
        Enum.map(#{var}, fn x -> MapSet.member?(set, ...) end)
    """
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

  # --- AST helpers ---

  defp extract_enum_call({{:., _, [{:__aliases__, _, [:Enum]}, func]}, meta, [arg | _]})
       when func in @enum_funcs do
    case var_name(arg) do
      nil -> :error
      var -> {:ok, func, var, meta}
    end
  end

  defp extract_enum_call(_), do: :error

  defp var_name({name, _, context}) when is_atom(name) and is_atom(context), do: name
  defp var_name(_), do: nil
end
