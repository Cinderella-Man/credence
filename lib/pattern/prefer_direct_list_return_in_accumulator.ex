defmodule Credence.Pattern.PreferDirectListReturnInAccumulator do
  @moduledoc """
  Detects functions that accumulate a list but return a tuple `{acc, []}` where
  the second element is always an empty list, when returning just the accumulator
  would suffice.

  ## Bad

      defp convert_to_stack(0, acc), do: {acc, []}

      # caller:
      {stack, _} = convert_to_stack(number, [])
      Enum.join(stack)

  ## Good

      defp convert_to_stack(0, acc), do: acc

      # caller:
      stack = convert_to_stack(number, [])
      Enum.join(stack)
  """
  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    # Collect function names that have the {acc, []} base-case pattern
    base_case_fns = find_tuple_base_cases(ast)

    if base_case_fns == %{} do
      []
    else
      # Walk the AST to find callers that destructure the result as {var, _}
      {_ast, issues} =
        Macro.prewalk(ast, [], fn node, acc ->
          case find_destructure_caller(node, base_case_fns) do
            {:ok, fn_name, line} ->
              issue = %Issue{
                rule: :prefer_direct_list_return_in_accumulator,
                message:
                  "`#{fn_name}` returns `{acc, []}` but the caller discards the second element. " <>
                    "Return just the accumulator instead.",
                meta: %{line: line}
              }

              {node, [issue | acc]}

            :error ->
              {node, acc}
          end
        end)

      Enum.reverse(issues)
    end
  end

  @impl true
  def fix_patches(ast, _opts) do
    base_case_fns = find_tuple_base_cases(ast)

    if base_case_fns == %{} do
      []
    else
      RuleHelpers.patches_from_postwalk(ast, fn node ->
        rewrite_node(node, base_case_fns)
      end)
    end
  end

  # Walk the AST to find defp clauses whose body is {acc, []} where acc is a
  # parameter. Returns a map %{fn_name => true} for matching.
  defp find_tuple_base_cases(ast) do
    {_ast, fns} =
      Macro.prewalk(ast, %{}, fn
        {:defp, _meta, [{name, _, params}, body_kw]}, acc
        when is_atom(name) and is_list(params) and is_list(body_kw) ->
          if tuple_base_case?(body_kw, params) do
            {nil, Map.put(acc, name, true)}
          else
            {nil, acc}
          end

        {:defp, _meta, [{:when, _, [{name, _, params}, _guard]}, body_kw]}, acc
        when is_atom(name) and is_list(params) and is_list(body_kw) ->
          if tuple_base_case?(body_kw, params) do
            {nil, Map.put(acc, name, true)}
          else
            {nil, acc}
          end

        node, acc ->
          {node, acc}
      end)

    fns
  end

  # Check if a defp body returns {param, []} where param is one of the function's
  # parameters and [] is an empty list literal.
  defp tuple_base_case?(body_kw, params) when is_list(body_kw) do
    case RuleHelpers.extract_do_body(body_kw) do
      {:ok, body} ->
        case extract_tuple_pair(body) do
          {:ok, first, second} ->
            is_param_var?(first, params) and is_empty_list_literal?(second)

          :error ->
            false
        end

      :error ->
        false
    end
  end

  defp tuple_base_case?(_, _), do: false

  # Extract {first, second} from a tuple literal in the AST.
  # Sourceror wraps tuple literals as {:__block__, meta, [{first, second}]}
  defp extract_tuple_pair({:__block__, _meta, [{first, second}]})
       when is_tuple(first) and tuple_size(first) == 2 and
              is_tuple(second) and tuple_size(second) == 2 do
    # This is a 2-element list, not a tuple pair
    :error
  end

  defp extract_tuple_pair({:__block__, _meta, [{first, second}]}) do
    {:ok, first, second}
  end

  defp extract_tuple_pair(_), do: :error

  defp is_param_var?({name, _, ctx}, params)
       when is_atom(name) and (is_nil(ctx) or is_atom(ctx)) do
    Enum.any?(params, fn
      {^name, _, _} -> true
      _ -> false
    end)
  end

  defp is_param_var?(_, _), do: false

  defp is_empty_list_literal?({:__block__, _meta, [[]]}), do: true
  defp is_empty_list_literal?(_), do: false

  # Find callers that destructure the result as {var, _} = fn_call(...)
  defp find_destructure_caller(
         {:=, _meta,
          [
            {:__block__, _block_meta, [{{var_name, _, var_ctx}, {:_, _, _}}]},
            {fn_name, _call_meta, _args}
          ]},
         base_case_fns
       )
       when is_atom(var_name) and (is_nil(var_ctx) or is_atom(var_ctx)) and
              is_atom(fn_name) do
    if Map.has_key?(base_case_fns, fn_name) do
      line = get_line_from_caller(var_name, var_ctx)
      {:ok, fn_name, line}
    else
      :error
    end
  end

  defp find_destructure_caller(_, _), do: :error

  defp get_line_from_caller(_var_name, var_ctx) when is_list(var_ctx),
    do: Keyword.get(var_ctx, :line)

  defp get_line_from_caller(_, _), do: nil

  # Rewrite nodes: change {acc, []} base cases to acc, and {var, _} = fn() to var = fn()
  defp rewrite_node(
         {:defp, meta, [{name, name_meta, params}, body_kw]},
         base_case_fns
       )
       when is_atom(name) and is_list(params) and is_list(body_kw) do
    if Map.has_key?(base_case_fns, name) and tuple_base_case?(body_kw, params) do
      case RuleHelpers.extract_do_body(body_kw) do
        {:ok, body} ->
          case extract_tuple_pair(body) do
            {:ok, first, _second} ->
              new_body_kw = RuleHelpers.replace_do_body(body_kw, first)
              {:defp, meta, [{name, name_meta, params}, new_body_kw]}

            :error ->
              {:defp, meta, [{name, name_meta, params}, body_kw]}
          end

        :error ->
          {:defp, meta, [{name, name_meta, params}, body_kw]}
      end
    else
      {:defp, meta, [{name, name_meta, params}, body_kw]}
    end
  end

  defp rewrite_node(
         {:defp, meta, [{:when, when_meta, [{name, name_meta, params}, guard]}, body_kw]},
         base_case_fns
       )
       when is_atom(name) and is_list(params) and is_list(body_kw) do
    if Map.has_key?(base_case_fns, name) and tuple_base_case?(body_kw, params) do
      case RuleHelpers.extract_do_body(body_kw) do
        {:ok, body} ->
          case extract_tuple_pair(body) do
            {:ok, first, _second} ->
              new_body_kw = RuleHelpers.replace_do_body(body_kw, first)

              {:defp, meta, [{:when, when_meta, [{name, name_meta, params}, guard]}, new_body_kw]}

            :error ->
              {:defp, meta, [{:when, when_meta, [{name, name_meta, params}, guard]}, body_kw]}
          end

        :error ->
          {:defp, meta, [{:when, when_meta, [{name, name_meta, params}, guard]}, body_kw]}
      end
    else
      {:defp, meta, [{:when, when_meta, [{name, name_meta, params}, guard]}, body_kw]}
    end
  end

  defp rewrite_node(
         {:=, assign_meta,
          [
            {:__block__, _block_meta, [{{var_name, var_meta, var_ctx}, {:_, _, _}}]},
            {fn_name, _call_meta, _args} = call
          ]},
         base_case_fns
       )
       when is_atom(var_name) and is_atom(fn_name) do
    if Map.has_key?(base_case_fns, fn_name) do
      # Rewrite {var, _} = fn(...) to var = fn(...)
      {:=, assign_meta, [{var_name, var_meta, var_ctx}, call]}
    else
      {:=, assign_meta,
       [
         {:__block__, [], [{{var_name, var_meta, var_ctx}, {:_, [], nil}}]},
         call
       ]}
    end
  end

  defp rewrite_node(node, _base_case_fns), do: node
end
