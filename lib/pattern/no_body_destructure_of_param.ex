defmodule Credence.Pattern.NoBodyDestructureOfParam do
  @moduledoc """
  Readability rule: Detects pattern matches at the start of a function body
  where the right-hand side is a function parameter, when the structural
  destructure could be moved to the function head for clearer, more idiomatic
  code.

  Only flags when:
  - The match is the first expression in the function body
  - The right-hand side is a simple variable that is a function parameter
  - The left-hand side is a non-trivial structural pattern (not just a variable)
  - The parameter is not referenced in the guard clause
  - The parameter is not referenced in the remaining body after the match

  ## Bad

      def process(list) do
        [head | tail] = list
        head
      end

      def handle(response) do
        {status, body} = response
        status
      end

  ## Good

      def process([head | tail]) do
        head
      end

      def handle({status, body}) do
        status
      end
  """
  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {kind, _meta, args} = node, issues when kind in [:def, :defp] and is_list(args) ->
          case extract_body_destructure(node) do
            nil -> {node, issues}
            info -> {node, [build_issue(info) | issues]}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # Extract body destructure from a def/defp node.
  defp extract_body_destructure({kind, _meta, head_and_body})
       when kind in [:def, :defp] do
    case parse_head(head_and_body) do
      nil ->
        nil

      {call, guard, body} ->
        {_name, _, params} = call
        param_names = extract_param_names(params)

        body_exprs =
          case body do
            {:__block__, _, exprs} -> exprs
            single -> [single]
          end

        case body_exprs do
          [{:=, meta, [pattern, {param_name, _, ctx}]} | rest]
          when is_atom(param_name) and is_atom(ctx) ->
            if param_name in param_names and
                 non_trivial_pattern?(pattern) and
                 not var_used_in?(guard, param_name) and
                 not var_used_in_body?(rest, param_name) do
              %{param: param_name, pattern: pattern, line: Keyword.get(meta, :line)}
            end

          _ ->
            nil
        end
    end
  end

  # Parse function head, handling both guarded and unguarded forms.
  # Sourceror uses {{:__block__, _, [:do]}, body} for the do block.
  defp parse_head([{:when, _, [call, guard]}, do_kw_list]) do
    case RuleHelpers.extract_do_body(do_kw_list) do
      {:ok, body} -> {call, guard, body}
      :error -> nil
    end
  end

  defp parse_head([call, do_kw_list]) do
    case RuleHelpers.extract_do_body(do_kw_list) do
      {:ok, body} -> {call, nil, body}
      :error -> nil
    end
  end

  defp parse_head(_), do: nil

  # Extract simple variable names from the parameter list.
  defp extract_param_names(params) when is_list(params) do
    for {name, _, context} <- params, is_atom(name), is_atom(context), do: name
  end

  defp extract_param_names(_), do: []

  # A simple variable binding (x = ...) is trivial. Anything else
  # ([a | b] = ..., {a, b} = ..., %{k: v} = ...) is non-trivial.
  defp non_trivial_pattern?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: false
  defp non_trivial_pattern?(_), do: true

  # Check whether a variable name is referenced anywhere in an AST subtree.
  defp var_used_in?(nil, _var_name), do: false

  defp var_used_in?(ast, var_name) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {name, _, ctx} = node, acc when is_atom(name) and is_atom(ctx) ->
          {node, acc or name == var_name}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # Check whether a variable name is referenced in any of the body expressions.
  defp var_used_in_body?(exprs, var_name) when is_list(exprs) do
    Enum.any?(exprs, &var_used_in?(&1, var_name))
  end

  defp build_issue(%{param: param, pattern: pattern, line: line}) do
    %Issue{
      rule: :no_body_destructure_of_param,
      message:
        "Pattern match `#{Macro.to_string(pattern)} = #{param}` in function body " <>
          "can be moved to the function head for clearer code.",
      meta: %{line: line}
    }
  end
end
