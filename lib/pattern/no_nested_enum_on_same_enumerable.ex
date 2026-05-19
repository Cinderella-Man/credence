defmodule Credence.Pattern.NoNestedEnumOnSameEnumerable do
  @moduledoc """
  Detects `Enum.member?/2` calls nested inside another `Enum.*` traversal
  of the **same** enumerable and rewrites them to use `MapSet.member?/2`.

  ## Bad
      Enum.map(list, fn x ->
        Enum.member?(list, x + 1)
      end)

  ## Good
      set = MapSet.new(list)

      Enum.map(list, fn x ->
        MapSet.member?(set, x + 1)
      end)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

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

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)
    RuleHelpers.patches_from_ast_transform(ast, source, &transform_ast/1)
  end

  # For each outer `Enum.<func>(var, ...)` whose body contains a nested
  # `Enum.member?(var, value)` call on the *same* variable: wrap the
  # outer call in a `:__block__` of [`set = MapSet.new(var)`, rewritten
  # call] and rewrite the inner `member?` calls to `MapSet.member?/2`.
  defp transform_ast(ast) do
    Macro.prewalk(ast, &maybe_wrap_outer_call/1)
  end

  defp maybe_wrap_outer_call(
         {{:., _, [{:__aliases__, _, [:Enum]}, func]}, _, [arg | _]} = node
       )
       when func in @enum_funcs and func != :member? do
    with var when not is_nil(var) <- var_name(arg),
         true <- has_nested_member?(node, var) do
      set_var = {:set, [], nil}
      rewritten = rewrite_inner_members(node, var, set_var)

      set_assign =
        {:=, [], [set_var, {{:., [], [{:__aliases__, [], [:MapSet]}, :new]}, [], [arg]}]}

      {:__block__, [], [set_assign, rewritten]}
    else
      _ -> node
    end
  end

  defp maybe_wrap_outer_call(node), do: node

  defp has_nested_member?(node, target_var) do
    {_ast, found} =
      Macro.prewalk(node, false, fn
        {{:., _, [{:__aliases__, _, [:Enum]}, :member?]}, _, [{^target_var, _, ctx}, _]} = n, _
        when is_atom(ctx) or is_nil(ctx) ->
          {n, true}

        n, acc ->
          {n, acc}
      end)

    found
  end

  defp rewrite_inner_members(node, target_var, set_var) do
    Macro.prewalk(node, fn
      {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, :member?]}, call_meta,
       [{^target_var, _, ctx}, value_arg]}
      when is_atom(ctx) or is_nil(ctx) ->
        # Preserve the original call's line/column meta so Sourceror's
        # renderer keeps the call on its original line span instead of
        # falling back to wide-span multi-line layout.
        {{:., dot_meta, [{:__aliases__, alias_meta, [:MapSet]}, :member?]}, call_meta,
         [set_var, value_arg]}

      n ->
        n
    end)
  end

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
