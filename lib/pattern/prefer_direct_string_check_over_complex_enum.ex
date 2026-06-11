defmodule Credence.Pattern.PreferDirectStringCheckOverComplexEnum do
  @moduledoc """
  Detects dead `Enum.all?` code that precedes a simpler direct
  `String.duplicate` comparison, and uses `rem/2` instead of
  `Integer.mod/2` for clarity.

  ## Bad

      defp validate_pattern(string, count, divisor) do
        repeat_count = div(count, divisor)

        if Integer.mod(count, divisor) == 0 do
          pattern = String.slice(string, 0, divisor)
          Enum.all?(0..(repeat_count - 1), fn i ->
            start = i * divisor
            String.slice(string, start, count - start) == pattern and
              (start + count == count or
                 String.slice(string, start + divisor, count) != pattern)
          end)
          # More straightforward check:
          full_pattern = String.duplicate(pattern, repeat_count)
          string == full_pattern
        else
          false
        end
      end

  ## Good

      defp validate_pattern(string, count, divisor) do
        if rem(count, divisor) == 0 do
          pattern = String.slice(string, 0, divisor)
          String.duplicate(pattern, div(count, divisor)) == string
        else
          false
        end
      end
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case detect_pattern(node) do
          {:ok, line} ->
            issue = %Issue{
              rule: :prefer_direct_string_check_over_complex_enum,
              message:
                "Dead `Enum.all?` check before direct `String.duplicate` comparison. " <>
                  "Use `rem/2` instead of `Integer.mod/2` and remove dead code.",
              meta: %{line: line}
            }

            {node, [issue | issues]}

          :error ->
            {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.get(opts, :source, "")

    RuleHelpers.patches_from_ast_transform(ast, source, fn ast ->
      Macro.postwalk(ast, fn node ->
        case transform_node(node) do
          {:ok, new_node} -> new_node
          :error -> node
        end
      end)
    end)
  end

  # ── Detection ────────────────────────────────────────────────────────

  defp detect_pattern({:defp, meta, [_head, body_kw]}) when is_list(body_kw) do
    with {:ok, body} <- extract_do_body(body_kw),
         {:ok, {:__block__, _, [binding, if_expr]}} <- {:ok, body},
         {:ok, _repeat_name, count_var, divisor_var} <- extract_repeat_binding(binding),
         true <- anti_pattern_if?(if_expr, count_var, divisor_var) do
      {:ok, meta[:line]}
    else
      _ -> :error
    end
  end

  defp detect_pattern(_), do: :error

  defp extract_do_body(kw) when is_list(kw) do
    Enum.find_value(kw, :error, fn
      {{:__block__, _, [:do]}, body} -> {:ok, body}
      {:do, body} -> {:ok, body}
      _ -> nil
    end)
  end

  defp extract_do_body(_), do: :error

  defp extract_repeat_binding({:=, _, [{name, _, nil}, {:div, _, [count, divisor]}]})
       when is_atom(name) do
    {:ok, name, count, divisor}
  end

  defp extract_repeat_binding(_), do: :error

  defp anti_pattern_if?({:if, _, [condition, clauses]}, count_var, divisor_var) do
    integer_mod_zero?(condition, count_var, divisor_var) and
      if_do_block_valid?(clauses) and
      if_else_false?(clauses)
  end

  defp anti_pattern_if?(_, _, _), do: false

  defp integer_mod_zero?({:==, _, [mod_expr, {:__block__, _, [0]}]}, count_var, divisor_var) do
    integer_mod_call?(mod_expr, count_var, divisor_var)
  end

  defp integer_mod_zero?(_, _, _), do: false

  defp integer_mod_call?(
         {{:., _, [{:__aliases__, _, [:Integer]}, :mod]}, _, [count, divisor]},
         count_var,
         divisor_var
       ) do
    same_var?(count, count_var) and same_var?(divisor, divisor_var)
  end

  defp integer_mod_call?(_, _, _), do: false

  defp same_var?({name, _, _}, {name, _, _}) when is_atom(name), do: true
  defp same_var?(_, _), do: false

  defp if_else_false?(clauses) do
    case extract_clause(clauses, :else) do
      {:ok, {:__block__, _, [false]}} -> true
      _ -> false
    end
  end

  defp if_do_block_valid?(clauses) do
    case extract_clause(clauses, :do) do
      {:ok, {:__block__, _, stmts}} when length(stmts) == 4 ->
        match_do_block?(stmts)

      _ ->
        false
    end
  end

  defp match_do_block?(
         [
           {:=, _, [{:pattern, _, nil}, slice_call]},
           enum_all_call,
           {:=, _, [{:full_pattern, _, nil}, dup_call]},
           {:==, _, [string_var, {:full_pattern, _, nil}]}
         ]
       ) do
    string_slice?(slice_call) and
      dead_enum_all?(enum_all_call) and
      string_duplicate?(dup_call) and
      is_var?(string_var)
  end

  defp match_do_block?(_), do: false

  defp string_slice?({{:., _, [{:__aliases__, _, [:String]}, :slice]}, _, _}), do: true
  defp string_slice?(_), do: false

  defp dead_enum_all?({{:., _, [{:__aliases__, _, [:Enum]}, :all?]}, _, _}), do: true
  defp dead_enum_all?(_), do: false

  defp string_duplicate?({{:., _, [{:__aliases__, _, [:String]}, :duplicate]}, _, _}),
    do: true

  defp string_duplicate?(_), do: false

  defp is_var?({name, _, ctx}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)), do: true
  defp is_var?(_), do: false

  defp extract_clause(clauses, key) when is_list(clauses) do
    Enum.find_value(clauses, :error, fn
      {{:__block__, _, [^key]}, body} -> {:ok, body}
      {^key, body} -> {:ok, body}
      _ -> nil
    end)
  end

  defp extract_clause(_, _), do: :error

  # ── Transformation ───────────────────────────────────────────────────

  defp transform_node({:defp, meta, [head, body_kw]}) when is_list(body_kw) do
    with {:ok, body} <- extract_do_body(body_kw),
         {:ok, {:__block__, bmeta, [binding, if_expr]}} <- {:ok, body},
         {:ok, _repeat_name, count_var, divisor_var} <- extract_repeat_binding(binding),
         true <- anti_pattern_if?(if_expr, count_var, divisor_var) do
      new_if = build_new_if(if_expr, count_var, divisor_var)
      new_body_kw = replace_do_body(body_kw, {:__block__, bmeta, [new_if]})
      {:ok, {:defp, meta, [head, new_body_kw]}}
    else
      _ -> :error
    end
  end

  defp transform_node(_), do: :error

  defp build_new_if({:if, if_meta, [_condition, clauses]}, count_var, divisor_var) do
    new_condition =
      {:==, [],
       [
         {:rem, [], [count_var, divisor_var]},
         {:__block__, [], [0]}
       ]}

    case extract_clause(clauses, :do) do
      {:ok, {:__block__, do_meta, stmts}} ->
        pattern_binding = Enum.at(stmts, 0)
        new_comparison = build_new_comparison(stmts, count_var, divisor_var)
        new_do_body = {:__block__, do_meta, [pattern_binding, new_comparison]}

        case extract_clause(clauses, :else) do
          {:ok, else_body} ->
            {:if, if_meta, [new_condition, [do: new_do_body, else: else_body]]}

          :error ->
            {:if, if_meta, [new_condition, [do: new_do_body]]}
        end

      _ ->
        {:if, if_meta, [new_condition, clauses]}
    end
  end

  defp build_new_comparison(stmts, count_var, divisor_var) do
    {:==, _, [string_var, _full_pattern]} = Enum.at(stmts, 3)

    {:==, [],
     [
       {{:., [], [{:__aliases__, [], [:String]}, :duplicate]}, [],
        [
          {:pattern, [], nil},
          {:div, [], [count_var, divisor_var]}
        ]},
       string_var
     ]}
  end

  defp replace_do_body(kw, new_body) when is_list(kw) do
    Enum.map(kw, fn
      {{:__block__, meta, [:do]}, _} -> {{:__block__, meta, [:do]}, new_body}
      other -> other
    end)
  end

  defp replace_do_body(kw, _), do: kw
end
