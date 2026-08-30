defmodule Credence.Pattern.NoReduceForGroupBy do
  @moduledoc """
  Detects a manual `Enum.group_by/2` written as `Enum.reduce/3` with an
  empty-map accumulator that prepends each element onto a per-key list via
  `Map.update(acc, key, [elem], &[elem | &1])`, **immediately followed by**
  `|> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)` to restore insertion
  order.

  Only this complete pipeline is flagged, because only this complete pipeline
  is exactly equivalent to `Enum.group_by/2` on every input.

  ## Why the full pipeline is required

  The bare reduce builds each value list in **reverse** insertion order (prepend
  with `[elem | &1]`):

      Enum.reduce(["a1", "a2"], %{}, fn x, acc ->
        Map.update(acc, String.first(x), [x], &[x | &1])
      end)
      #=> %{"a" => ["a2", "a1"]}

  whereas `Enum.group_by/2` keeps insertion order (`%{"a" => ["a1", "a2"]}`).
  The trailing `Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)` reverses each
  value list, making the whole expression equal to:

      Enum.group_by(enum, fn x -> String.first(x) end)

  A bare reduce **without** the reverse is therefore *not* flagged: it produces
  a different (reverse-order) result, so there is no behaviour-preserving fix.

  ## Flagged pattern (auto-fixed)

      Enum.reduce(enum, %{}, fn x, acc ->
        Map.update(acc, key(x), [x], &[x | &1])
      end)
      |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)

  becomes

      Enum.group_by(enum, fn x -> key(x) end)

  The reduce may be written directly (`Enum.reduce(enum, %{}, fn ...)`) or piped
  (`enum |> Enum.reduce(%{}, fn ...)`). The key may be computed inline in the
  `Map.update` call, or via a single `key = ...` binding immediately preceding
  the `Map.update` (the only other statement in the function body).

  ## Bad

      defmodule BadNRFGB do
        def group(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            Map.update(acc, String.first(x), [x], &[x | &1])
          end)
          |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
        end
      end

  ## Good

      defmodule BadNRFGB do
        def group(list) do
          Enum.group_by(
            list,
            fn x -> String.first(x) end
          )
        end
      end
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

  # The check fires on exactly the shape the fix rewrites, and nothing else:
  # `<reduce> |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)` where the
  # reduce is a group_by-shaped reduce. This guarantees check and fix agree.
  defp check_node({:|>, pipe_meta, [reduce_node, map_new_node]}) do
    with {:ok, _enum, _key_fn} <- extract_group_by_reduce(reduce_node),
         :ok <- match_reverse_map_new(map_new_node) do
      {:ok, build_issue(pipe_meta)}
    else
      _ -> :error
    end
  end

  defp check_node(_), do: :error

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

  # Extract the key expression from the reduce body.
  #
  # Two safe shapes are accepted:
  #   1. The body is a single `Map.update(acc, key_expr, [elem], &[elem | &1])`.
  #   2. The body is a two-statement block `key = key_expr; Map.update(acc, key,
  #      [elem], &[elem | &1])` — exactly one binding feeding the key, with the
  #      `Map.update` as the returned (last) statement.
  #
  # Anything else (extra statements, side effects, `Map.update` not last) is
  # rejected: dropping or reordering those statements would not preserve
  # behaviour, so there is no safe fix.
  defp extract_key_from_body(body, elem, acc) do
    case body do
      # 1. Single Map.update call (the function body / returned value)
      {{:., _, [{:__aliases__, _, [:Map]}, :update]}, _,
       [acc_var, key_expr, default_arg, update_fn]} ->
        if valid_map_update?(acc_var, acc, default_arg, update_fn, elem) and
             accumulator_independent?(key_expr, acc) do
          {:ok, key_expr}
        else
          :error
        end

      # 2. Block: exactly `key = key_expr` then `Map.update(acc, key, ...)`
      {:__block__, _,
       [
         {:=, _, [{key_var, _, key_ctx}, key_expr]},
         {{:., _, [{:__aliases__, _, [:Map]}, :update]}, _,
          [acc_var, {map_key, _, map_key_ctx}, default_arg, update_fn]}
       ]}
      when is_atom(key_var) and is_atom(key_ctx) and is_atom(map_key) and is_atom(map_key_ctx) ->
        if map_key == key_var and
             valid_map_update?(acc_var, acc, default_arg, update_fn, elem) and
             accumulator_independent?(key_expr, acc) do
          {:ok, key_expr}
        else
          :error
        end

      _ ->
        :error
    end
  end

  # The Map.update call accumulates onto `acc`, defaults to `[elem]`, and
  # prepends with `&[elem | &1]` — i.e. it builds a per-key list in reverse
  # insertion order, the half of group_by that the trailing reverse undoes.
  defp valid_map_update?(acc_var, acc, default_arg, update_fn, elem) do
    match_acc?(acc_var, acc) and group_by_default?(default_arg, elem) and
      group_by_update_fn?(update_fn, elem)
  end

  defp match_acc?({acc, _, ctx}, acc) when is_atom(ctx), do: true
  defp match_acc?(_, _), do: false

  defp accumulator_independent?(key_expr, acc) do
    {_key_expr, references_acc?} =
      Macro.prewalk(key_expr, false, fn
        {^acc, _, ctx} = node, _references_acc? when is_atom(ctx) -> {node, true}
        node, references_acc? -> {node, references_acc?}
      end)

    not references_acc?
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
        "`Enum.reduce/3` building a map via `Map.update/4` with list prepend, " <>
          "then `Map.new` reversing each value list, is a manual implementation " <>
          "of `Enum.group_by/2`. " <>
          "`Enum.group_by(enum, fn elem -> key end)` is clearer and more idiomatic.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
