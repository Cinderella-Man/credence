defmodule Credence.Pattern.NoIfEmptyForEnumMinMax do
  @moduledoc """
  Flags `if var == [], do: default, else: Enum.min(var)` (and `Enum.max`).
  Prefer `Enum.min(var, fn -> default end)` with the `empty_fallback` parameter.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:if, meta, [condition, opts]} = node, issues ->
          if match = detect_empty_guard(condition, opts) do
            issue = %Issue{
              rule: :no_if_empty_for_enum_min_max,
              message:
                "Prefer #{match.enum_fn}/#{match.arity} with empty_fallback instead of `if var == []` guard.",
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
      {:if, _meta, [condition, opts]} = node ->
        case detect_empty_guard(condition, opts) do
          %{var: var, default: default, enum_fn: enum_fn} ->
            build_enum_call(enum_fn, var, default)

          nil ->
            node
        end

      node ->
        node
    end)
  end

  # Detect `if var == [], do: default, else: Enum.min(var)` or Enum.max(var)
  # Also detects `if var != [], do: Enum.min(var), else: default`
  defp detect_empty_guard(condition, opts) do
    with {:ok, do_expr} <- fetch_kw_value(opts, :do),
         {:ok, else_expr} <- fetch_kw_value(opts, :else) do
      detect_eq_empty(condition, do_expr, else_expr) ||
        detect_neq_empty(condition, do_expr, else_expr)
    else
      _ -> nil
    end
  end

  # `if var == [], do: default, else: Enum.min(var)`
  defp detect_eq_empty({:==, _, [var, empty]}, default, enum_call) do
    if empty_list_literal?(empty) do
      case enum_min_max_call(enum_call, var) do
        {enum_fn, matched_var, arity} ->
          %{var: matched_var, default: default, enum_fn: enum_fn, arity: arity}

        nil ->
          nil
      end
    end
  end

  defp detect_eq_empty(_, _, _), do: nil

  # `if var != [], do: Enum.min(var), else: default`
  defp detect_neq_empty({:!=, _, [var, empty]}, enum_call, default) do
    if empty_list_literal?(empty) do
      case enum_min_max_call(enum_call, var) do
        {enum_fn, matched_var, arity} ->
          %{var: matched_var, default: default, enum_fn: enum_fn, arity: arity}

        nil ->
          nil
      end
    end
  end

  defp detect_neq_empty(_, _, _), do: nil

  # Sourceror wraps [] as {:__block__, _, [[]]}
  defp empty_list_literal?([]), do: true
  defp empty_list_literal?({:__block__, _, [[]]}), do: true
  defp empty_list_literal?(_), do: false

  # Match `Enum.min(var)` or `Enum.max(var)` and verify it uses the same var
  defp enum_min_max_call({{:., _, [{:__aliases__, _, [:Enum]}, fn_name]}, _, [arg]}, var)
       when fn_name in [:min, :max] do
    if same_var?(arg, var), do: {fn_name, arg, 1}, else: nil
  end

  defp enum_min_max_call(_, _), do: nil

  defp same_var?({name, _, ctx1}, {name, _, ctx2})
       when is_atom(name) and is_atom(ctx1) and is_atom(ctx2),
       do: true

  defp same_var?(_, _), do: false

  defp build_enum_call(fn_name, var, default) do
    # Enum.min(var, fn -> default end) or Enum.max(var, fn -> default end)
    fallback_fn = {:fn, [], [{:->, [], [[], default]}]}

    {{:., [], [{:__aliases__, [], [:Enum]}, fn_name]}, [], [var, fallback_fn]}
  end

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
end
