defmodule Credence.Pattern.NoIfEmptyForEnumMinMax do
  @moduledoc """
  Flags `if Enum.empty?(var), do: default, else: Enum.min(var)` (and `Enum.max`),
  and the negated form `if !Enum.empty?(var), do: Enum.min(var), else: default`
  (also `not Enum.empty?(var)`).

  Prefer `Enum.min(var, fn -> default end)` with the `empty_fallback` parameter.

  The guarded enumerable may be a bare variable or an `Enum.filter/2` /
  `Enum.reject/2` call — as long as the **same** expression appears in both the
  `Enum.empty?(...)` guard and the `Enum.min/max(...)` branch. This catches the
  common "max of the matching elements, or a default if there are none" shape:

      if Enum.empty?(Enum.filter(nums, pred)),
        do: nil,
        else: Enum.max(Enum.filter(nums, pred))
      #  →  Enum.max(Enum.filter(nums, pred), fn -> nil end)

  Only the `Enum.empty?/1` forms are flagged. The `if var == []` /
  `if var != []` and `case var do [] -> default; v -> Enum.min(v) end` forms are
  deliberately NOT flagged: their empty test only matches the literal empty list,
  so on a non-list empty enumerable (`%{}`, an empty range, an empty `MapSet`) the
  original takes the non-empty branch and `Enum.min(var)` raises `Enum.EmptyError`,
  while `Enum.min(var, fn -> default end)` returns the default — a behaviour
  change. `Enum.empty?/1` reports emptiness for every enumerable, matching
  `Enum.min/2`'s empty_fallback exactly, so those forms rewrite identically.

  The guarded expression is restricted to a bare variable or an
  `Enum.filter/2` / `Enum.reject/2` call so the only re-evaluated work is a
  predicate (the original already evaluates the expression twice: once in the
  guard, once in the branch). This matches the purity convention the other
  filter-based structural rules rely on.
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
                "Prefer #{match.enum_fn}/#{match.arity} with empty_fallback instead of `if Enum.empty?` check.",
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
          %{enum_expr: enum_expr, default: default, enum_fn: enum_fn} ->
            build_enum_call(enum_fn, enum_expr, default)

          nil ->
            node
        end

      node ->
        node
    end)
  end

  # Detect `if Enum.empty?(var), do: default, else: Enum.min(var)` (or Enum.max),
  # and the negated `if !Enum.empty?(var), do: Enum.min(var), else: default`.
  defp detect_empty_guard(condition, opts) do
    with {:ok, do_expr} <- fetch_kw_value(opts, :do),
         {:ok, else_expr} <- fetch_kw_value(opts, :else) do
      detect_enum_empty(condition, do_expr, else_expr) ||
        detect_negated_enum_empty(condition, do_expr, else_expr)
    else
      _ -> nil
    end
  end

  # `if Enum.empty?(expr), do: default, else: Enum.min(expr)`
  defp detect_enum_empty(
         {{:., _, [{:__aliases__, _, [:Enum]}, :empty?]}, _, [guard_expr]},
         default,
         enum_call
       ) do
    case enum_min_max_call(enum_call, guard_expr) do
      {enum_fn, matched_expr, arity} ->
        %{enum_expr: matched_expr, default: default, enum_fn: enum_fn, arity: arity}

      nil ->
        nil
    end
  end

  defp detect_enum_empty(_, _, _), do: nil

  # `if !Enum.empty?(expr), do: Enum.min(expr), else: default`
  # `if not Enum.empty?(expr), do: Enum.min(expr), else: default`
  defp detect_negated_enum_empty(
         {neg, _,
          [
            {{:., _, [{:__aliases__, _, [:Enum]}, :empty?]}, _, [guard_expr]}
          ]},
         enum_call,
         default
       )
       when neg in [:!, :not] do
    case enum_min_max_call(enum_call, guard_expr) do
      {enum_fn, matched_expr, arity} ->
        %{enum_expr: matched_expr, default: default, enum_fn: enum_fn, arity: arity}

      nil ->
        nil
    end
  end

  defp detect_negated_enum_empty(_, _, _), do: nil

  # Match `Enum.min(expr)` or `Enum.max(expr)` where `expr` is an eligible
  # enumerable (a bare var or an `Enum.filter/2` / `Enum.reject/2` call) and is
  # the SAME expression as the one tested by `Enum.empty?` in the guard.
  defp enum_min_max_call({{:., _, [{:__aliases__, _, [:Enum]}, fn_name]}, _, [arg]}, guard_expr)
       when fn_name in [:min, :max] do
    if eligible_enum_expr?(arg) and same_expr?(arg, guard_expr) do
      {fn_name, arg, 1}
    else
      nil
    end
  end

  defp enum_min_max_call(_, _), do: nil

  # A bare variable...
  defp eligible_enum_expr?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true

  # ...or an `Enum.filter(_, _)` / `Enum.reject(_, _)` call (pure modulo predicate).
  defp eligible_enum_expr?({{:., _, [{:__aliases__, _, [:Enum]}, fun]}, _, [_enum, _pred]})
       when fun in [:filter, :reject],
       do: true

  defp eligible_enum_expr?(_), do: false

  # Structural equality ignoring metadata (line numbers, Sourceror wrappers'
  # positions) so two textually-identical expressions compare equal.
  defp same_expr?(a, b), do: strip_meta(a) == strip_meta(b)

  defp strip_meta(ast) do
    Macro.prewalk(ast, fn
      {form, _meta, args} -> {form, [], args}
      other -> other
    end)
  end

  defp build_enum_call(fn_name, enum_expr, default) do
    # Enum.min(enum_expr, fn -> default end) / Enum.max(enum_expr, fn -> default end)
    fallback_fn = {:fn, [], [{:->, [], [[], default]}]}

    {{:., [], [{:__aliases__, [], [:Enum]}, fn_name]}, [], [enum_expr, fallback_fn]}
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
