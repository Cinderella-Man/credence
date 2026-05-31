defmodule Credence.Pattern.NoExplicitMinReduce do
  @moduledoc "Flags explicit min-reduction patterns inside Enum.reduce/3."

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., _, _}, meta, args} = node, issues ->
          if reduce_call?(node) and min_reduce_body?(args) do
            issue = %Issue{
              rule: :no_explicit_min_reduce,
              message: "Explicit min-reduction detected. Prefer Enum.min/1 or Enum.min_by/2.",
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
        if reduce_call?(node) and min_reduce_body?(args) do
          [enum | _] = args
          enum_min_call(enum)
        else
          node
        end

      node ->
        node
    end)
  end

  defp enum_min_call(enum) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :min]}, [], [enum]}
  end

  defp reduce_call?({{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, _}), do: true
  defp reduce_call?({{:., _, [:Enum, :reduce]}, _, _}), do: true
  defp reduce_call?(_), do: false

  defp min_reduce_body?([_enum, _acc, {:fn, _, [{:->, _, [args, body]}]}]) do
    case List.last(args) do
      {acc_name, _, _} when is_atom(acc_name) -> explicit_min?(body, acc_name)
      _ -> false
    end
  end

  defp min_reduce_body?(_), do: false

  defp explicit_min?({:__block__, _, [_ | _] = exprs}, acc_name) do
    explicit_min?(List.last(exprs), acc_name)
  end

  defp explicit_min?({:min, _, [a, b]}, acc_name) do
    var_name?(a, acc_name) or var_name?(b, acc_name)
  end

  defp explicit_min?({:if, _, [{:<, _, [a, b]}, opts]}, acc_name) do
    (var_name?(a, acc_name) or var_name?(b, acc_name)) and min_if_branches?(opts, a, b)
  end

  defp explicit_min?({:if, _, [{:<=, _, [a, b]}, opts]}, acc_name) do
    (var_name?(a, acc_name) or var_name?(b, acc_name)) and min_if_branches?(opts, a, b)
  end

  defp explicit_min?(_, _), do: false

  defp min_if_branches?(opts, a, b) when is_list(opts) do
    with {:ok, do_expr} <- fetch_kw_value(opts, :do),
         {:ok, else_expr} <- fetch_kw_value(opts, :else) do
      (var_match?(do_expr, a) and var_match?(else_expr, b)) or
        (var_match?(do_expr, b) and var_match?(else_expr, a))
    else
      _ -> false
    end
  end

  defp min_if_branches?(_, _, _), do: false

  # Sourceror wraps keyword keys as {{:__block__, _, [:key]}, value}
  defp fetch_kw_value(opts, key) do
    case Keyword.get(opts, key) do
      nil ->
        Enum.find_value(opts, :error, fn
          {{:__block__, _, [^key]}, value} -> {:ok, value}
          _ -> nil
        end)

      value ->
        {:ok, value}
    end
  end

  defp var_name?({name, _, _}, target) when is_atom(name), do: name == target
  defp var_name?(_, _), do: false

  defp var_match?({name, _, _}, {target_name, _, _}) when is_atom(name) and is_atom(target_name),
    do: name == target_name

  defp var_match?(_, _), do: false
end
