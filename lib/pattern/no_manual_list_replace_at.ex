defmodule Credence.Pattern.NoManualListReplaceAt do
  @moduledoc """
  Detects hand-rolled reimplementations of `List.replace_at/3` via
  `Enum.split/2` followed by list concatenation.

  ## Why this matters

  When code needs to replace an element at a specific index in a list,
  the standard library provides `List.replace_at/3`. LLMs sometimes
  reimplement this as:

      defp replace_at(list, index, value) do
        {left, [_ | right]} = Enum.split(list, index)
        left ++ [value] ++ right
      end

  This is functionally identical to `List.replace_at(list, index, value)`
  but adds unnecessary code and obscures intent.

  ## Detection scope

  A `defp` (or `def`) function with arity 3 where:
  1. The body calls `Enum.split/2` (or `List.split/2`) on the first parameter
  2. The result is destructured as `{left, [_ | right]}`
  3. The function returns `left ++ [third_param] ++ right`

  ## Auto-fix

  Replaces the function body with a delegation to `List.replace_at/3`.
  """

  use Credence.Pattern.Rule
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case detect_pattern(node) do
          {:ok, meta} -> {node, [build_issue(meta) | acc]}
          :error -> {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)
    matches = find_matching_functions(ast)

    if Enum.empty?(matches) do
      []
    else
      RuleHelpers.patches_from_ast_transform(ast, source, fn input ->
        transform_ast(input, matches)
      end)
    end
  end

  # --- detection ---

  defp detect_pattern({def_type, meta, [head, body_kw | _rest]})
       when def_type in [:def, :defp] and is_list(body_kw) do
    with {:ok, _fn_name, params} <- extract_fn_head(head, 3),
         {:ok, body} <- RuleHelpers.extract_do_body(body_kw),
         true <- replace_at_pattern?(body, params) do
      {:ok, %{line: meta[:line]}}
    else
      _ -> :error
    end
  end

  defp detect_pattern(_), do: :error

  defp extract_fn_head({fn_name, _, params}, expected_arity)
       when is_atom(fn_name) and is_list(params) and length(params) == expected_arity do
    {:ok, fn_name, params}
  end

  defp extract_fn_head({:when, _, [{fn_name, _, params}, _guard]}, expected_arity)
       when is_atom(fn_name) and is_list(params) and length(params) == expected_arity do
    {:ok, fn_name, params}
  end

  defp extract_fn_head(_, _), do: :error

  defp replace_at_pattern?(body, params) do
    case unwrap_block(body) do
      [split_expr, concat_expr] ->
        split_matches?(split_expr, params) and concat_matches?(concat_expr)

      _ ->
        false
    end
  end

  defp unwrap_block({:__block__, _, exprs}), do: exprs
  defp unwrap_block(single), do: [single]

  # {left, [_ | right]} = Enum.split(list_param, index_param)
  defp split_matches?({:=, _, [destructure, split_call]}, params) do
    tuple_destructure?(destructure) and split_call?(split_call, params)
  end

  defp split_matches?(_, _), do: false

  # Sourceror format: 2-tuple wrapped in __block__
  defp tuple_destructure?({:__block__, _, [{left_var, cons_pattern}]}) do
    cons_destructure?(cons_pattern) and var?(left_var)
  end

  # Standard Elixir format: 2-tuple
  defp tuple_destructure?({left_var, cons_pattern}) do
    cons_destructure?(cons_pattern) and var?(left_var)
  end

  defp tuple_destructure?(_), do: false

  # Sourceror format: cons pattern wrapped in __block__
  defp cons_destructure?({:__block__, _, [[{:|, _, [head, tail]}]]}) do
    wildcard?(head) and var?(tail)
  end

  # Standard Elixir format: cons pattern
  defp cons_destructure?({:|, _, [head, tail]}) do
    wildcard?(head) and var?(tail)
  end

  defp cons_destructure?(_), do: false

  defp wildcard?({:_, _, ctx}) when is_atom(ctx), do: true

  defp wildcard?({name, _, ctx}) when is_atom(name) and is_atom(ctx) do
    String.starts_with?(Atom.to_string(name), "_")
  end

  defp wildcard?(_), do: false

  defp var?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp var?(_), do: false

  # Enum.split(list_param, index_param) or List.split(list_param, index_param)
  defp split_call?({{:., _, [{:__aliases__, _, module}, :split]}, _, [arg1, arg2]}, params)
       when module in [[:Enum], [:List]] do
    param1_name = param_name(params, 0)
    param2_name = param_name(params, 1)
    matches_param?(arg1, param1_name) and matches_param?(arg2, param2_name)
  end

  defp split_call?(_, _), do: false

  defp param_name(params, index) do
    case Enum.at(params, index) do
      {name, _, _} when is_atom(name) -> name
      _ -> nil
    end
  end

  defp matches_param?({name, _, ctx}, expected) when is_atom(name) and is_atom(ctx) do
    name == expected
  end

  defp matches_param?(_, _), do: false

  # left ++ [value_param] ++ right
  # Sourceror format: [value] wrapped in __block__
  defp concat_matches?({:++, _, [left_var, {:++, _, [{:__block__, _, [[value_var]]}, right_var]}]}) do
    var?(left_var) and var?(right_var) and var?(value_var)
  end

  # Standard Elixir format: [value] as list
  defp concat_matches?({:++, _, [left_var, {:++, _, [[value_var], right_var]}]}) do
    var?(left_var) and var?(right_var) and var?(value_var)
  end

  defp concat_matches?(_), do: false

  # --- fix ---

  defp find_matching_functions(ast) do
    {_ast, matches} =
      Macro.prewalk(ast, [], fn node, acc ->
        case detect_pattern(node) do
          {:ok, _meta} ->
            case node do
              {def_type, _, [head | _]} ->
                {:ok, fn_name, _} = extract_fn_head(head, 3)
                {node, [{fn_name, def_type} | acc]}

              _ ->
                {node, acc}
            end

          :error ->
            {node, acc}
        end
      end)

    MapSet.new(matches)
  end

  defp transform_ast(node, matches) do
    case node do
      {def_type, meta, [head, body_kw | rest]} when def_type in [:def, :defp] ->
        case extract_fn_head(head, 3) do
          {:ok, fn_name, params} ->
            if MapSet.member?(matches, {fn_name, def_type}) do
              [list_param, index_param, value_param] = params

              list_replace_call =
                {{:., [], [{:__aliases__, [], [:List]}, :replace_at]}, [],
                 [list_param, index_param, value_param]}

              new_body_kw = replace_do_body(body_kw, list_replace_call)
              {def_type, meta, [head, new_body_kw | rest]}
            else
              walk_node(node, matches)
            end

          _ ->
            walk_node(node, matches)
        end

      _ ->
        walk_node(node, matches)
    end
  end

  defp walk_node({tag, meta, args}, matches) when is_list(args) do
    {tag, meta, Enum.map(args, &transform_ast(&1, matches))}
  end

  defp walk_node({left, right}, matches) do
    {transform_ast(left, matches), transform_ast(right, matches)}
  end

  defp walk_node(list, matches) when is_list(list) do
    Enum.map(list, &transform_ast(&1, matches))
  end

  defp walk_node(node, _matches), do: node

  defp replace_do_body([{{:__block__, meta, [:do]}, _body} | rest], new_body) do
    [{{:__block__, meta, [:do]}, new_body} | rest]
  end

  defp replace_do_body([{:do, _body} | rest], new_body) do
    [{:do, new_body} | rest]
  end

  defp replace_do_body(other, _new_body), do: other

  defp build_issue(meta) do
    %Issue{
      rule: :no_manual_list_replace_at,
      message:
        "This function manually reimplements `List.replace_at/3` via " <>
          "`Enum.split/2` and list concatenation. " <>
          "Replace the body with `List.replace_at(list, index, value)`.",
      meta: %{line: meta.line}
    }
  end
end
