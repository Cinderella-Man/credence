defmodule Credence.Pattern.PreferEnumCount do
  @moduledoc """
  Detects `Enum.reduce/3` calls that count elements matching a predicate
  (using 0 as initial accumulator and `if pred, do: acc + 1, else: acc` as body)
  and rewrites them to the more concise `Enum.count/2`.

  ## Bad

      values
      |> Enum.reduce(0, fn count, odd_count ->
        if rem(count, 2) == 1, do: odd_count + 1, else: odd_count
      end)

  ## Good

      values
      |> Enum.count(&(rem(&1, 2) == 1))
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., _, _}, meta, args} = node, issues ->
          if counting_reduce?(node, args) do
            issue = %Issue{
              rule: :prefer_enum_count,
              message:
                "Enum.reduce with counting if-body reimplements Enum.count/2. " <>
                  "Use Enum.count/2 with a predicate instead.",
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
        case build_count_call(node, args) do
          {:ok, new_node} -> new_node
          :error -> node
        end

      node ->
        node
    end)
  end

  # ── Pattern detection ──────────────────────────────────────────────

  defp counting_reduce?(node, args) do
    reduce_call?(node) and counting_body?(args)
  end

  defp reduce_call?({{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, _}), do: true
  defp reduce_call?(_), do: false

  # 3-arg form: Enum.reduce(enum, 0, fn ...)
  defp counting_body?([_enum, acc_init, fn_expr]) do
    zero?(acc_init) and counting_fn?(fn_expr)
  end

  # 2-arg form (piped): Enum.reduce(0, fn ...)
  defp counting_body?([acc_init, fn_expr]) do
    zero?(acc_init) and counting_fn?(fn_expr)
  end

  defp counting_body?(_), do: false

  defp zero?({:__block__, _, [0]}), do: true
  defp zero?(_), do: false

  defp counting_fn?({:fn, _, [{:->, _, [[_elem_var, acc_var], body]}]}) do
    var?(acc_var) and counting_if?(body, acc_var)
  end

  defp counting_fn?(_), do: false

  defp counting_if?({:if, _, [_condition, clauses]}, acc_var) when is_list(clauses) do
    do_body = extract_keyword_clause(clauses, :do)
    else_body = extract_keyword_clause(clauses, :else)
    acc_increment?(do_body, acc_var) and same_var?(else_body, acc_var)
  end

  defp counting_if?(_, _), do: false

  # acc + 1 or 1 + acc
  defp acc_increment?({:+, _, [left, right]}, acc_var) do
    (same_var?(left, acc_var) and literal_one?(right)) or
      (literal_one?(left) and same_var?(right, acc_var))
  end

  defp acc_increment?(_, _), do: false

  defp same_var?({name, _, ctx1}, {name, _, ctx2})
       when is_atom(name) and (is_nil(ctx1) or is_atom(ctx1)) and
              (is_nil(ctx2) or is_atom(ctx2)),
       do: true

  defp same_var?(_, _), do: false

  defp var?({name, _, ctx}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)), do: true
  defp var?(_), do: false

  defp literal_one?({:__block__, _, [1]}), do: true
  defp literal_one?(1), do: true
  defp literal_one?(_), do: false

  defp extract_keyword_clause(clauses, key) do
    Enum.find_value(clauses, fn
      {{:__block__, _, [^key]}, body} -> body
      _ -> nil
    end)
  end

  # ── Fix transformation ─────────────────────────────────────────────

  defp build_count_call(_node, args) do
    case args do
      # 3-arg form: Enum.reduce(enum, 0, fn ...)
      [enum, acc_init, fn_expr] ->
        if zero?(acc_init) do
          case extract_predicate(fn_expr) do
            {:ok, elem_name, _acc_name, condition} ->
              capture = build_capture(condition, elem_name)

              {:ok, {{:., [], [{:__aliases__, [], [:Enum]}, :count]}, [], [enum, capture]}}

            :error ->
              :error
          end
        else
          :error
        end

      # 2-arg form (piped): Enum.reduce(0, fn ...)
      [acc_init, fn_expr] ->
        if zero?(acc_init) do
          case extract_predicate(fn_expr) do
            {:ok, elem_name, _acc_name, condition} ->
              capture = build_capture(condition, elem_name)

              {:ok, {{:., [], [{:__aliases__, [], [:Enum]}, :count]}, [], [capture]}}

            :error ->
              :error
          end
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp extract_predicate({:fn, _, [{:->, _, [[elem_var, acc_var], body]}]}) do
    if var?(elem_var) and var?(acc_var) do
      case body do
        {:if, _, [condition, clauses]} when is_list(clauses) ->
          do_body = extract_keyword_clause(clauses, :do)
          else_body = extract_keyword_clause(clauses, :else)

          if acc_increment?(do_body, acc_var) and same_var?(else_body, acc_var) do
            {:ok, elem(elem_var, 0), elem(acc_var, 0), condition}
          else
            :error
          end

        _ ->
          :error
      end
    else
      :error
    end
  end

  defp extract_predicate(_), do: :error

  defp build_capture(predicate, elem_name) do
    replaced =
      Macro.prewalk(predicate, fn
        {^elem_name, _, ctx} when (is_nil(ctx) or is_atom(ctx)) and is_atom(elem_name) ->
          {:&, [], [1]}

        node ->
          node
      end)

    {:&, [], [replaced]}
  end
end
