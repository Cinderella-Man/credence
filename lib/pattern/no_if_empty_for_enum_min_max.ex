defmodule Credence.Pattern.NoIfEmptyForEnumMinMax do
  @moduledoc """
  Flags `if Enum.empty?(var), do: default, else: Enum.min(var)` (and `Enum.max`),
  and the negated form `if !Enum.empty?(var), do: Enum.min(var), else: default`
  (also `not Enum.empty?(var)`).

  Prefer `Enum.min(var, fn -> default end)` with the `empty_fallback` parameter.

  Only the `Enum.empty?/1` forms are flagged. The `if var == []` /
  `if var != []` and `case var do [] -> default; v -> Enum.min(v) end` forms are
  deliberately NOT flagged: their empty test only matches the literal empty list,
  so on a non-list empty enumerable (`%{}`, an empty range, an empty `MapSet`) the
  original takes the non-empty branch and `Enum.min(var)` raises `Enum.EmptyError`,
  while `Enum.min(var, fn -> default end)` returns the default — a behaviour
  change. `Enum.empty?/1` reports emptiness for every enumerable, matching
  `Enum.min/2`'s empty_fallback exactly, so those forms rewrite identically.

  ## Bad

      defmodule Bad do
        def run(lengths) do
          if Enum.empty?(lengths), do: 0, else: Enum.min(lengths)
        end
      end

  ## Good

      defmodule Bad do
        def run(lengths) do
          Enum.min(lengths, fn -> 0 end)
        end
      end
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
          %{var: var, default: default, enum_fn: enum_fn} ->
            build_enum_call(enum_fn, var, default)

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

  # `if Enum.empty?(var), do: default, else: Enum.min(var)`
  defp detect_enum_empty(
         {{:., _, [{:__aliases__, _, [:Enum]}, :empty?]}, _, [var]},
         default,
         enum_call
       ) do
    case enum_min_max_call(enum_call, var) do
      {enum_fn, matched_var, arity} ->
        %{var: matched_var, default: default, enum_fn: enum_fn, arity: arity}

      nil ->
        nil
    end
  end

  defp detect_enum_empty(_, _, _), do: nil

  # `if !Enum.empty?(var), do: Enum.min(var), else: default`
  # `if not Enum.empty?(var), do: Enum.min(var), else: default`
  defp detect_negated_enum_empty(
         {neg, _,
          [
            {{:., _, [{:__aliases__, _, [:Enum]}, :empty?]}, _, [var]}
          ]},
         enum_call,
         default
       )
       when neg in [:!, :not] do
    case enum_min_max_call(enum_call, var) do
      {enum_fn, matched_var, arity} ->
        %{var: matched_var, default: default, enum_fn: enum_fn, arity: arity}

      nil ->
        nil
    end
  end

  defp detect_negated_enum_empty(_, _, _), do: nil

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

  # Sourceror wraps keyword keys as {{:__block__, _, [:key]}, value}.
  # `opts` is the second arg of an `if` node. For the standard `if cond, do:…`
  # form it is a keyword list, but a custom `if`/2 macro (e.g. Nx's
  # `defmacro if(pred, do_else)` or Explorer's query DSL) can pass a bare
  # variable there — guard so the rule degrades to "no match" instead of
  # crashing on `Keyword.get/3`.
  defp fetch_kw_value(opts, _key) when not is_list(opts), do: :error

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
