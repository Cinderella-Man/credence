defmodule Credence.Pattern.NoGroupByForFrequencies do
  @moduledoc """
  Detects `Enum.group_by(enum, key_fn) |> Map.new(fn {k, group} -> {k, length(group)} end)`
  which counts occurrences by key — exactly what `Enum.frequencies_by/2` does, but with
  unnecessary intermediate per-group lists.

  ## Bad

      Enum.group_by(words, &String.downcase/1)
      |> Map.new(fn {key, group} -> {key, length(group)} end)

      Map.new(Enum.group_by(words, &String.downcase/1), fn {k, g} -> {k, length(g)} end)

  ## Good

      Enum.frequencies_by(words, &String.downcase/1)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    ast = mask_shadowed_local_length(ast)

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
    ast = mask_shadowed_local_length(ast)

    Credence.RuleHelpers.patches_from_postwalk(ast, fn node ->
      case fix_node(node) do
        {:ok, replacement} -> replacement
        :error -> node
      end
    end)
  end

  # Pipeline: enum |> ... |> Enum.group_by(key_fn) |> Map.new(callback)
  #
  # We only flag when `Enum.group_by` is in *piped* position with exactly one
  # explicit argument (the key_fn) — that is the safe `group_by/2` form, and the
  # fix can recover the enum from the steps before it. A `value_fun` (i.e.
  # `group_by/3`, two explicit args in pipe position) is deliberately *not*
  # flagged: `frequencies_by/2` never calls it, so dropping a side-effecting or
  # raising `value_fun` would change the answer. See `group_by_step?/1`.
  #
  # We look only at the *terminal* two steps so each occurrence is reported
  # exactly once: every occurrence has a left-nested `|>` subnode that ends at
  # its `Map.new` step, and `Macro.prewalk` visits that subnode. Requiring at
  # least three steps guarantees there is an enum before the `group_by`.
  # 2-step piped: Enum.group_by(enum, key_fn) |> Map.new(cb) / |> Enum.into(%{}, cb)
  # (group_by called with the enum as an explicit arg, then piped to the collector).
  defp check_node(
         {:|>, _,
          [
            {{:., meta, [{:__aliases__, _, [:Enum]}, :group_by]}, _, [_enum, _key_fn]},
            collector
          ]}
       ) do
    case count_collector(collector) do
      {:ok, callback} ->
        if length_of_group_fn?(callback), do: {:ok, build_issue(meta)}, else: :error

      :error ->
        :error
    end
  end

  defp check_node({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    if length(steps) >= 3 do
      [first, second] = Enum.take(steps, -2)

      if group_by_step?(first) and map_new_length_step?(second) do
        {{:., meta, _}, _, _} = first
        {:ok, build_issue(meta)}
      else
        :error
      end
    else
      :error
    end
  end

  # Direct: Map.new(Enum.group_by(enum, key_fn), callback)
  defp check_node(
         {{:., meta, [{:__aliases__, _, [:Map]}, :new]}, _,
          [
            {{:., _, [{:__aliases__, _, [:Enum]}, :group_by]}, _, [_enum, _key_fn]},
            callback
          ]}
       ) do
    if length_of_group_fn?(callback) do
      {:ok, build_issue(meta)}
    else
      :error
    end
  end

  defp check_node(_), do: :error

  # 2-step piped: Enum.group_by(enum, key_fn) |> Map.new(cb) / |> Enum.into(%{}, cb)
  defp fix_node(
         {:|>, _,
          [
            {{:., meta, [{:__aliases__, _, [:Enum]}, :group_by]}, _, [enum, key_fn]},
            collector
          ]}
       ) do
    case count_collector(collector) do
      {:ok, callback} ->
        if length_of_group_fn?(callback),
          do: {:ok, frequencies_call(enum, key_fn, meta)},
          else: :error

      :error ->
        :error
    end
  end

  defp fix_node({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    case find_group_by_frequencies_pair(steps) do
      {:ok, before_steps, group_by_step, _map_new_step, after_steps} ->
        {{:., _, _}, _, group_by_args} = group_by_step
        # In pipe form, group_by has 1 arg (the key_fn)
        key_fn = hd(group_by_args)

        enum_source =
          case before_steps do
            [] ->
              # enum was consumed in the pipe; we can't extract it cleanly
              # from the pipeline steps alone — fall back to not fixing
              nil

            [single] ->
              single

            multiple ->
              Enum.reduce(tl(multiple), hd(multiple), fn step, acc ->
                {:|>, [], [acc, step]}
              end)
          end

        if enum_source do
          {{:., meta, _}, _, _} = group_by_step

          frequencies_by = frequencies_call(enum_source, key_fn, meta)

          case after_steps do
            [] ->
              {:ok, frequencies_by}

            remaining ->
              rebuilt =
                Enum.reduce(remaining, frequencies_by, fn step, acc ->
                  {:|>, [], [acc, step]}
                end)

              {:ok, rebuilt}
          end
        else
          :error
        end

      _ ->
        :error
    end
  end

  # Direct: Map.new(Enum.group_by(enum, key_fn), callback)
  defp fix_node(
         {{:., meta, [{:__aliases__, _, [:Map]}, :new]}, _,
          [
            {{:., _, [{:__aliases__, _, [:Enum]}, :group_by]}, _, [enum, key_fn]},
            callback
          ]}
       ) do
    if length_of_group_fn?(callback) do
      {:ok, frequencies_call(enum, key_fn, meta)}
    else
      :error
    end
  end

  defp fix_node(_), do: :error

  # Map.new(cb) or Enum.into(%{}, cb) — both build the {element => count} map.
  defp count_collector({{:., _, [{:__aliases__, _, [:Map]}, :new]}, _, [callback]}),
    do: {:ok, callback}

  defp count_collector(
         {{:., _, [{:__aliases__, _, [:Enum]}, :into]}, _, [{:%{}, _, []}, callback]}
       ),
       do: {:ok, callback}

  defp count_collector(_), do: :error

  # `Enum.frequencies/1` when the key_fn is the identity (cleaner), else
  # `Enum.frequencies_by/2`.
  defp frequencies_call(enum, key_fn, meta) do
    if identity_fn?(key_fn) do
      {{:., [], [{:__aliases__, [], [:Enum]}, :frequencies]}, meta, [enum]}
    else
      {{:., [], [{:__aliases__, [], [:Enum]}, :frequencies_by]}, meta, [enum, key_fn]}
    end
  end

  defp identity_fn?({:&, _, [{:&, _, [1]}]}), do: true
  defp identity_fn?({:&, _, [{:__block__, _, [{:&, _, [1]}]}]}), do: true

  defp identity_fn?({:fn, _, [{:->, _, [[{v, _, c}], {v, _, c}]}]})
       when is_atom(v) and is_atom(c),
       do: true

  defp identity_fn?(_), do: false

  defp find_group_by_frequencies_pair(steps) do
    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.find_value(fn {[first, second], idx} ->
      if group_by_step?(first) and map_new_length_step?(second) do
        before = Enum.take(steps, idx)
        after_ = Enum.drop(steps, idx + 2)
        {:ok, before, first, second, after_}
      end
    end)
  end

  # Piped `Enum.group_by/2`: exactly one explicit arg (the key_fn); the enum is
  # piped in. Two explicit args here means `group_by/3` (a `value_fun`), which is
  # NOT a safe rewrite to `frequencies_by/2` — see `check_node/1`.
  defp group_by_step?({{:., _, [{:__aliases__, _, [:Enum]}, :group_by]}, _, [_key_fn]}),
    do: true

  defp group_by_step?(_), do: false

  defp map_new_length_step?({{:., _, [{:__aliases__, _, [:Map]}, :new]}, _, [callback]}),
    do: length_of_group_fn?(callback)

  defp map_new_length_step?(_), do: false

  # Checks that the callback is of the form: fn {k, group} -> {k, length(group)} end
  # Sourceror wraps 2-tuples in {:__block__, _, [tuple]}, so we handle both
  # the wrapped and unwrapped forms.

  # 3+ element tuple form: fn {a, b, c} -> ... — uses {:{}} tag
  defp length_of_group_fn?(
         {:fn, _,
          [
            {:->, _,
             [
               [{:{}, _, [k_var, g_var]}],
               {:{}, _, [k_var2, length_call]}
             ]}
          ]}
       ) do
    same_var?(k_var, k_var2) and length_call_on?(length_call, g_var)
  end

  # 2-tuple form, Sourceror-wrapped: fn {k, group} -> {k, length(group)} end
  defp length_of_group_fn?(
         {:fn, _,
          [
            {:->, _,
             [
               [{:__block__, _, [{k_var, g_var}]}],
               {:__block__, _, [{k_var2, length_call}]}
             ]}
          ]}
       ) do
    same_var?(k_var, k_var2) and length_call_on?(length_call, g_var)
  end

  # 2-tuple form, raw: fn {k, group} -> {k, length(group)} end
  defp length_of_group_fn?(
         {:fn, _,
          [
            {:->, _,
             [
               [{k_var, g_var}],
               {k_var2, length_call}
             ]}
          ]}
       ) do
    same_var?(k_var, k_var2) and length_call_on?(length_call, g_var)
  end

  defp length_of_group_fn?(_), do: false

  # length(group_var) — local call
  defp length_call_on?({:length, _, [{var, _, ctx}]}, {var, _, ctx})
       when is_atom(var) and is_atom(ctx),
       do: true

  # Kernel.length(group_var) — remote call
  defp length_call_on?(
         {{:., _, [{:__aliases__, _, [:Kernel]}, :length]}, _, [{var, _, ctx}]},
         {var, _, ctx}
       )
       when is_atom(var) and is_atom(ctx),
       do: true

  # Enum.count(group_var) — also counts elements
  defp length_call_on?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, [{var, _, ctx}]},
         {var, _, ctx}
       )
       when is_atom(var) and is_atom(ctx),
       do: true

  defp length_call_on?(_, _), do: false

  defp same_var?({name, _, ctx}, {name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp same_var?(_, _), do: false

  # A local length/1 definition takes precedence over the normally imported
  # Kernel.length/1. Keep those calls opaque so this rule does not silently
  # replace application behaviour with a count.
  defp mask_shadowed_local_length(ast) do
    if defines_local_length?(ast) do
      Macro.prewalk(ast, fn
        {:length, meta, [arg]} -> {:__credence_shadowed_length__, meta, [arg]}
        node -> node
      end)
    else
      ast
    end
  end

  defp defines_local_length?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {kind, _, [{:length, _, args} | _]} = node, _found?
        when kind in [:def, :defp, :defmacro, :defmacrop] and length(args) == 1 ->
          {node, true}

        node, found? ->
          {node, found?}
      end)

    found?
  end

  defp flatten_pipeline({:|>, _, [left, right]}),
    do: flatten_pipeline(left) ++ [right]

  defp flatten_pipeline(expr), do: [expr]

  defp build_issue(meta) do
    %Issue{
      rule: :no_group_by_for_frequencies,
      message:
        "`Enum.group_by/2` piped into `Map.new/2` counting group lengths is a manual " <>
          "frequency-by-key computation. Use `Enum.frequencies_by/2` instead — it is clearer, " <>
          "avoids intermediate per-group lists, and is optimized internally.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
