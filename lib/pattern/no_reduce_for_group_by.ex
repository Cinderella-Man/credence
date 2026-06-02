defmodule Credence.Pattern.NoReduceForGroupBy do
  @moduledoc """
  Detects `Enum.reduce/3` with an empty-map accumulator `%{}` and a body
  using `Map.update/4` with list prepend (`[elem | &1]`), which is a manual
  implementation of `Enum.group_by/2`.

  When the reduce is followed by `Map.new/1` reversing each value list
  (in a pipeline), the entire expression is exactly `Enum.group_by/2` and
  an auto-fix is provided. Otherwise, the pattern is flagged as a check-only
  issue.

  ## Why this matters

  LLMs frequently produce:

      Enum.reduce(list, %{}, fn x, acc ->
        Map.update(acc, String.first(x), [x], &[x | &1])
      end)
      |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)

  when the idiomatic Elixir equivalent is:

      Enum.group_by(list, &String.first/1)

  `Enum.group_by/2` communicates intent directly and avoids manual
  accumulator threading.

  ## Flagged patterns

  | Pattern | Suggested replacement |
  | ------- | --------------------- |
  | `Enum.reduce(enum, %{}, fn x, acc -> Map.update(acc, k, [x], &[x \| &1]) end) \|> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)` | `Enum.group_by(enum, fn x -> k end)` |
  | `Enum.reduce(enum, %{}, fn x, acc -> Map.update(acc, k, [x], &[x \| &1]) end)` (no reverse) | `Enum.group_by(enum, fn x -> k end)` (check-only) |

  ## Auto-fix scope

  The auto-fix is provided only when the reduce is piped into `Map.new/1`
  that reverses each value list. The standalone reduce (without reverse)
  produces groups in reverse insertion order, which differs from
  `Enum.group_by/2`, so it is flagged but not auto-fixed.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case check_node(node) do
          {:ok, issue} -> {node, [issue | issues]}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      # Piped form: Enum.reduce(...) |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
      {:|>, pipe_meta, [reduce_node, map_new_node]} = node ->
        with {:ok, enum, key_fn} <- extract_group_by_reduce(reduce_node),
             :ok <- match_reverse_map_new(map_new_node) do
          build_group_by(enum, key_fn, pipe_meta)
        else
          _ -> node
        end

      node ->
        node
    end)
  end

  # ── check ──────────────────────────────────────────────────────────────

  defp check_node(node) do
    with :error <- check_reduce_direct(node),
         :error <- check_reduce_piped(node) do
      :error
    end
  end

  # Direct: Enum.reduce(enum, %{}, fn elem, acc -> ... end)
  defp check_reduce_direct({{:., meta, [{:__aliases__, _, [:Enum]}, :reduce]}, _, args})
       when is_list(args) do
    case args do
      [_enum, {:%{}, _, []}, fn_ast] ->
        if group_by_fn?(fn_ast) do
          {:ok, build_issue(meta)}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp check_reduce_direct(_), do: :error

  # Piped: enum |> Enum.reduce(%{}, fn elem, acc -> ... end)
  defp check_reduce_piped({:|>, _meta, [_enum, reduce_call]}) do
    case reduce_call do
      {{:., meta, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [{:%{}, _, []}, fn_ast]} ->
        if group_by_fn?(fn_ast) do
          {:ok, build_issue(meta)}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp check_reduce_piped(_), do: :error

  # Check if the anonymous function matches the group_by pattern
  defp group_by_fn?({:fn, _, clauses}) do
    Enum.any?(clauses, fn
      {:->, _, [[{elem, _, ectx}, {acc, _, actx}], body]}
      when is_atom(elem) and is_atom(ectx) and is_atom(acc) and is_atom(actx) ->
        group_by_body?(body, elem, acc)

      _ ->
        false
    end)
  end

  defp group_by_fn?(_), do: false

  # Check if the body contains Map.update(acc, key, [elem], &[elem | &1])
  # Sourceror wraps list literals in {:__block__, _, [[...]]}
  defp group_by_body?(body, elem, acc) do
    case body do
      # Single Map.update call (may appear directly or inside a block wrapper)
      {{:., _, [{:__aliases__, _, [:Map]}, :update]}, _,
       [{acc2, _, actx2}, _key, default_arg, update_fn]}
      when is_atom(actx2) ->
        acc2 == acc and group_by_default?(default_arg, elem) and
          group_by_update_fn?(update_fn, elem)

      # Block with binding + Map.update
      {:__block__, _, stmts} when is_list(stmts) ->
        Enum.any?(stmts, fn
          {{:., _, [{:__aliases__, _, [:Map]}, :update]}, _,
           [{acc2, _, actx2}, _key, default_arg, update_fn]}
          when is_atom(actx2) ->
            acc2 == acc and group_by_default?(default_arg, elem) and
              group_by_update_fn?(update_fn, elem)

          _ ->
            false
        end)

      _ ->
        false
    end
  end

  # Check default value is [elem] — either as a list literal or
  # Sourceror's {:__block__, _, [[elem_var]]} wrapper
  defp group_by_default?([{elem, _, ectx}], elem) when is_atom(ectx), do: true
  defp group_by_default?({:__block__, _, [[{elem, _, ectx}]]}, elem) when is_atom(ectx), do: true
  defp group_by_default?(_, _), do: false

  # Check if the update function is &[elem | &1]
  # Sourceror wraps the list literal in {:__block__, _, [[cons_pair]]}
  defp group_by_update_fn?(update_fn, elem) do
    case update_fn do
      # With Sourceror __block__ wrapper
      {:&, _, [{:__block__, _, [[{:|, _, [{elem2, _, ectx2}, {:&, _, [1]}]}]]}]}
      when is_atom(ectx2) ->
        elem2 == elem

      # Without wrapper (plain AST)
      {:&, _, [{:|, _, [{elem2, _, ectx2}, {:&, _, [1]}]}]}
      when is_atom(ectx2) ->
        elem2 == elem

      _ ->
        false
    end
  end

  # ── fix ────────────────────────────────────────────────────────────────

  # Extract enum and key function from a reduce node
  defp extract_group_by_reduce(reduce_node) do
    case reduce_node do
      # Direct: Enum.reduce(enum, %{}, fn ... end)
      {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [enum, {:%{}, _, []}, fn_ast]} ->
        extract_group_by_fn(fn_ast, enum)

      # Piped: enum |> Enum.reduce(%{}, fn ... end)
      {:|>, _,
       [enum, {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [{:%{}, _, []}, fn_ast]}]} ->
        extract_group_by_fn(fn_ast, enum)

      _ ->
        :error
    end
  end

  defp extract_group_by_fn(
         {:fn, _, [{:->, _, [[{elem, _, ectx}, {acc, _, actx}], body]}]},
         enum
       )
       when is_atom(elem) and is_atom(ectx) and is_atom(acc) and is_atom(actx) do
    case extract_key_from_body(body, elem, acc) do
      {:ok, key_expr} ->
        key_fn = {:fn, [], [{:->, [], [[{elem, [], ectx}], key_expr]}]}
        {:ok, enum, key_fn}

      :error ->
        :error
    end
  end

  defp extract_group_by_fn(_, _), do: :error

  # Extract the key expression from the reduce body
  defp extract_key_from_body(body, elem, acc) do
    case body do
      # Single Map.update call
      {{:., _, [{:__aliases__, _, [:Map]}, :update]}, _,
       [acc_var, key_expr, default_arg, update_fn]} ->
        if match_acc?(acc_var, acc) and group_by_default?(default_arg, elem) and
             group_by_update_fn?(update_fn, elem) do
          {:ok, key_expr}
        else
          :error
        end

      # Block with binding + Map.update
      {:__block__, _, stmts} when is_list(stmts) ->
        extract_key_from_block(stmts, elem, acc)

      _ ->
        :error
    end
  end

  defp match_acc?({acc, _, ctx}, acc) when is_atom(ctx), do: true
  defp match_acc?(_, _), do: false

  defp extract_key_from_block(stmts, elem, acc) do
    # First, build a map of variable bindings
    bindings =
      Enum.reduce(stmts, %{}, fn
        {:=, _, [{var, _, var_ctx}, value]}, b when is_atom(var) and is_atom(var_ctx) ->
          Map.put(b, var, value)

        _, b ->
          b
      end)

    # Then, find the Map.update call and extract the key
    Enum.find_value(stmts, :error, fn
      {{:., _, [{:__aliases__, _, [:Map]}, :update]}, _,
       [acc_var, key_expr, default_arg, update_fn]} ->
        if match_acc?(acc_var, acc) and group_by_default?(default_arg, elem) and
             group_by_update_fn?(update_fn, elem) do
          # If key_expr is a variable, look up its binding
          case key_expr do
            {key_var, _, key_ctx} when is_atom(key_var) and is_atom(key_ctx) ->
              case Map.get(bindings, key_var) do
                nil -> {:ok, key_expr}
                bound_expr -> {:ok, bound_expr}
              end

            _ ->
              {:ok, key_expr}
          end
        else
          :error
        end

      _ ->
        nil
    end)
  end

  # Check if the Map.new node matches: Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
  # Sourceror wraps 2-tuple patterns in {:__block__, _, [plain_tuple]}
  defp match_reverse_map_new({{:., _, [{:__aliases__, _, [:Map]}, :new]}, _, [fn_ast]}) do
    case fn_ast do
      {:fn, _, [{:->, _, [args_list, body]}]} ->
        match_reverse_fn?(args_list, body)

      _ ->
        :error
    end
  end

  defp match_reverse_map_new(_), do: :error

  defp match_reverse_fn?([tuple_pattern], body) do
    with {:ok, k_var, v_var} <- extract_tuple_pattern(tuple_pattern),
         {:ok, ^k_var, reverse_call} <- extract_tuple_body(body),
         true <- reverse_call?(reverse_call, v_var) do
      :ok
    else
      _ -> :error
    end
  end

  defp match_reverse_fn?(_, _), do: :error

  # Extract {k, v} from tuple pattern, handling Sourceror's __block__ wrapper
  defp extract_tuple_pattern({:__block__, _, [tuple]}), do: extract_tuple_pattern(tuple)

  defp extract_tuple_pattern({{k, _, kctx}, {v, _, vctx}})
       when is_atom(k) and is_atom(kctx) and is_atom(v) and is_atom(vctx),
       do: {:ok, k, v}

  defp extract_tuple_pattern(_), do: :error

  # Extract {k, reverse_expr} from tuple body, handling __block__ wrapper
  defp extract_tuple_body({:__block__, _, [tuple]}), do: extract_tuple_body(tuple)

  defp extract_tuple_body({{k, _, kctx}, reverse_expr})
       when is_atom(k) and is_atom(kctx),
       do: {:ok, k, reverse_expr}

  defp extract_tuple_body(_), do: :error

  # Check if the expression is Enum.reverse(v_var)
  defp reverse_call?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, [{v, _, vctx}]},
         v
       )
       when is_atom(v) and is_atom(vctx),
       do: true

  defp reverse_call?(_, _), do: false

  # Build Enum.group_by(enum, key_fn)
  defp build_group_by(enum, key_fn, meta) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :group_by]}, meta, [enum, key_fn]}
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_reduce_for_group_by,
      message:
        "`Enum.reduce/3` building a map via `Map.update/4` with list prepend " <>
          "is a manual implementation of `Enum.group_by/2`. " <>
          "`Enum.group_by(enum, fn elem -> key end)` is clearer and more idiomatic.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
