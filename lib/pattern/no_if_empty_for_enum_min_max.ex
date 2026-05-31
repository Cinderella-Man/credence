defmodule Credence.Pattern.NoIfEmptyForEnumMinMax do
  @moduledoc """
  Flags `if var == [], do: default, else: Enum.min(var)` (and `Enum.max`),
  the equivalent `case` form:
  `case var do [] -> default; v -> Enum.min(v) end`,
  and the `Enum.empty?/1` variant:
  `if Enum.empty?(var), do: default, else: Enum.min(var)`.

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
                "Prefer #{match.enum_fn}/#{match.arity} with empty_fallback instead of `if` empty-list guard.",
              meta: %{line: Keyword.get(meta, :line)}
            }

            {node, [issue | issues]}
          else
            {node, issues}
          end

        {:case, meta, [_subject, clause_kw]} = node, issues ->
          case extract_case_clauses(clause_kw) do
            {:ok, clauses} ->
              case detect_case_empty_min_max(clauses) do
                %{enum_fn: enum_fn} ->
                  issue = %Issue{
                    rule: :no_if_empty_for_enum_min_max,
                    message:
                      "Prefer #{enum_fn}/2 with empty_fallback instead of `case` on empty list.",
                    meta: %{line: Keyword.get(meta, :line)}
                  }

                  {node, [issue | issues]}

                nil ->
                  {node, issues}
              end

            :error ->
              {node, issues}
          end

        {:case, meta, [clause_kw]} = node, issues ->
          case extract_case_clauses(clause_kw) do
            {:ok, clauses} ->
              case detect_case_empty_min_max(clauses) do
                %{enum_fn: enum_fn} ->
                  issue = %Issue{
                    rule: :no_if_empty_for_enum_min_max,
                    message:
                      "Prefer #{enum_fn}/2 with empty_fallback instead of `case` on empty list.",
                    meta: %{line: Keyword.get(meta, :line)}
                  }

                  {node, [issue | issues]}

                nil ->
                  {node, issues}
              end

            :error ->
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

      {:case, _meta, [subject, clause_kw]} = node ->
        case extract_case_clauses(clause_kw) do
          {:ok, clauses} ->
            case detect_case_empty_min_max(clauses) do
              %{default: default, enum_fn: enum_fn} ->
                build_enum_call(enum_fn, subject, default)

              nil ->
                node
            end

          :error ->
            node
        end

      {:case, _meta, [clause_kw]} = node ->
        case extract_case_clauses(clause_kw) do
          {:ok, clauses} ->
            case detect_case_empty_min_max(clauses) do
              %{default: default, enum_fn: enum_fn} ->
                build_enum_call(enum_fn, nil, default)

              nil ->
                node
            end

          :error ->
            node
        end

      node ->
        node
    end)
  end

  # Detect `if var == [], do: default, else: Enum.min(var)` or Enum.max(var)
  # Also detects `if var != [], do: Enum.min(var), else: default`
  # Also detects `if Enum.empty?(var), do: default, else: Enum.min(var)`
  # Also detects `if !Enum.empty?(var), do: Enum.min(var), else: default`
  defp detect_empty_guard(condition, opts) do
    with {:ok, do_expr} <- fetch_kw_value(opts, :do),
         {:ok, else_expr} <- fetch_kw_value(opts, :else) do
      detect_eq_empty(condition, do_expr, else_expr) ||
        detect_neq_empty(condition, do_expr, else_expr) ||
        detect_enum_empty(condition, do_expr, else_expr) ||
        detect_negated_enum_empty(condition, do_expr, else_expr)
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

  # Extract clauses from case expression keyword list
  # Handles both plain [do: clauses] and Sourceror-wrapped [{{:__block__, _, [:do]}, clauses}]
  defp extract_case_clauses([do: clauses]), do: {:ok, clauses}
  defp extract_case_clauses([{{:__block__, _, [:do]}, clauses}]), do: {:ok, clauses}
  defp extract_case_clauses(_), do: :error

  # Detect `case var do [] -> default; v -> Enum.min(v) end` (or Enum.max)
  defp detect_case_empty_min_max(clauses) when length(clauses) == 2 do
    [clause1, clause2] = clauses

    with {:empty, default} <- classify_case_clause(clause1),
         {:var, var, enum_call} <- classify_case_clause(clause2),
         {enum_fn, _, _} <- enum_min_max_call(enum_call, var) do
      %{default: default, enum_fn: enum_fn}
    else
      _ ->
        with {:empty, default} <- classify_case_clause(clause2),
             {:var, var, enum_call} <- classify_case_clause(clause1),
             {enum_fn, _, _} <- enum_min_max_call(enum_call, var) do
          %{default: default, enum_fn: enum_fn}
        else
          _ -> nil
        end
    end
  end

  defp detect_case_empty_min_max(_), do: nil

  defp classify_case_clause({:->, _, [[], default]}), do: {:empty, default}

  defp classify_case_clause({:->, _, [[{:__block__, _, [[]]}], default]}),
    do: {:empty, default}

  defp classify_case_clause({:->, _, [[{var, _, ctx}], enum_call]})
       when is_atom(var) and is_atom(ctx),
       do: {:var, {var, [], ctx}, enum_call}

  defp classify_case_clause(_), do: nil

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

  defp build_enum_call(fn_name, nil, default) do
    # Enum.min(fn -> default end) or Enum.max(fn -> default end)
    # Used when the subject comes from a pipe
    fallback_fn = {:fn, [], [{:->, [], [[], default]}]}

    {{:., [], [{:__aliases__, [], [:Enum]}, fn_name]}, [], [fallback_fn]}
  end

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
