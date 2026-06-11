defmodule Credence.Pattern.PreferEnumFrequencies do
  @moduledoc """
  Detects `Enum.group_by(fn x -> x end, fn x -> x end) |> Enum.map(fn {val, vals} -> {val, Enum.count(vals)} end)`
  which counts occurrences of each element — exactly what `Enum.frequencies/1` does,
  but with unnecessary intermediate per-element lists and a manual mapping step.

  Using `Enum.group_by/3` with two identity functions followed by an `Enum.map/2`
  that counts each group is an unnecessarily verbose reimplementation of
  `Enum.frequencies/1`. Both produce identical `%{val => count}` maps.

  NOTE: The fix requires downstream pipeline steps after the pattern (e.g.
  `Enum.sort`, `Enum.take`) to erase the type difference between the
  list-of-tuples output of `Enum.group_by |> Enum.map` and the map output
  of `Enum.frequencies`. Without downstream steps, the types differ and the
  rewrite is not behaviour-preserving.

  ## Bad

      nums
      |> Enum.group_by(fn x -> x end, fn x -> x end)
      |> Enum.map(fn {val, vals} -> {val, Enum.count(vals)} end)
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      |> Enum.take(k)
      |> Enum.map(&elem(&1, 0))

  ## Good

      nums
      |> Enum.frequencies()
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      |> Enum.take(k)
      |> Enum.map(&elem(&1, 0))
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
    Credence.RuleHelpers.patches_from_postwalk(ast, fn node ->
      case fix_node(node) do
        {:ok, replacement} -> replacement
        :error -> node
      end
    end)
  end

  # ── Check ──────────────────────────────────────────────────────────────

  # Pipeline: scan adjacent step pairs for the group_by |> map(count) pattern.
  # Requires at least one downstream step after the pattern (to erase the
  # list-of-tuples vs map type difference).
  defp check_node({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    case find_pattern_pair_with_index(steps) do
      {:ok, idx} ->
        group_by_step = Enum.at(steps, idx)
        {{:., meta, _}, _, _} = group_by_step
        {:ok, build_issue(meta)}

      :error ->
        :error
    end
  end

  # Direct: Enum.map(Enum.group_by(enum, key_fn, val_fn), fn {k, v} -> {k, count(v)} end)
  defp check_node(
         {{:., meta, [{:__aliases__, _, [:Enum]}, :map]}, _,
          [
            {{:., _, [{:__aliases__, _, [:Enum]}, :group_by]}, _, _} = group_by_call,
            callback
          ]}
       ) do
    if identity_group_by?(group_by_call) and is_count_of_vals_fn?(callback) do
      {:ok, build_issue(meta)}
    else
      :error
    end
  end

  defp check_node(_), do: :error

  # ── Fix ────────────────────────────────────────────────────────────────

  # Pipeline: find and replace the group_by |> map(count) pair.
  defp fix_node({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    case find_pattern_pair_with_index(steps) do
      {:ok, group_by_idx} ->
        before_steps = Enum.take(steps, group_by_idx)
        [_group_by_step, _map_step | after_steps] = Enum.drop(steps, group_by_idx)
        {{:., meta, _}, _, group_by_args} = Enum.at(steps, group_by_idx)

        enum_source =
          case group_by_args do
            [enum, _key_fn, _val_fn] -> extract_enum(before_steps, enum)
            [_key_fn, _val_fn] -> extract_enum(before_steps, nil)
          end

        if enum_source && after_steps != [] do
          build_fix(meta, enum_source, after_steps)
        else
          :error
        end

      :error ->
        :error
    end
  end

  # Direct: Enum.map(Enum.group_by(enum, key_fn, val_fn), fn {k, v} -> {k, count(v)} end)
  # NOTE: Direct form has no downstream steps, so the type change from
  # list-of-tuples to map means we cannot safely fix this. Return :error.
  defp fix_node(_), do: :error

  # ── Helpers ────────────────────────────────────────────────────────────

  # Find the group_by |> map(count) pattern pair and return its index.
  # Requires downstream steps after the pattern.
  defp find_pattern_pair_with_index(steps) do
    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.find_value(:error, fn {[first, second], idx} ->
      after_count = length(steps) - idx - 2

      if identity_group_by?(first) and map_count_step?(second) and after_count > 0 do
        {:ok, idx}
      end
    end)
  end

  defp build_fix(meta, enum_source, after_steps) do
    frequencies = enum_frequencies(meta, enum_source)

    case after_steps do
      [] ->
        {:ok, frequencies}

      remaining ->
        rebuilt =
          Enum.reduce(remaining, frequencies, fn step, acc ->
            {:|>, [], [acc, step]}
          end)

        {:ok, rebuilt}
    end
  end

  defp enum_frequencies(meta, enum) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :frequencies]}, meta, [enum]}
  end

  defp extract_enum([], enum), do: enum

  defp extract_enum(before_steps, _fallback) do
    case before_steps do
      [single] ->
        single

      multiple ->
        Enum.reduce(tl(multiple), hd(multiple), fn step, acc ->
          {:|>, [], [acc, step]}
        end)
    end
  end

  # Enum.group_by(enum, key_fn, val_fn) — 3 explicit args (direct form)
  defp identity_group_by?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :group_by]}, _, [_enum, key_fn, val_fn]}
       ) do
    identity_function?(key_fn) and identity_function?(val_fn)
  end

  # Enum.group_by(key_fn, val_fn) — 2 explicit args (piped form)
  defp identity_group_by?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :group_by]}, _, [key_fn, val_fn]}
       ) do
    identity_function?(key_fn) and identity_function?(val_fn)
  end

  defp identity_group_by?(_), do: false

  # Enum.map(step, fn {k, v} -> {k, count(v)} end) — counts group sizes
  defp map_count_step?({{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [callback]}),
    do: is_count_of_vals_fn?(callback)

  defp map_count_step?(_), do: false

  # & &1 — capture of first argument
  defp identity_function?({:&, _, [{:&, _, [n]}]}) when is_integer(n), do: n == 1

  # fn x -> x end
  defp identity_function?({:fn, _, [{:->, _, [[{name, _, ctx}], {name, _, ctx}]}]})
       when is_atom(name) and is_atom(ctx),
       do: true

  defp identity_function?(_), do: false

  # Checks that the callback is of the form: fn {k, vals} -> {k, count(vals)} end
  # where count is length/1, Enum.count/1, or Kernel.length/1.
  # Sourceror wraps 2-tuples in {:__block__, _, [tuple]}.

  # 3+ element tuple form: fn {a, b, c} -> ... — uses {:{}} tag
  defp is_count_of_vals_fn?(
         {:fn, _,
          [
            {:->, _,
             [
               [{:{}, _, [k_var, g_var]}],
               {:{}, _, [k_var2, count_call]}
             ]}
          ]}
       ) do
    same_var?(k_var, k_var2) and is_count_call_on?(count_call, g_var)
  end

  # 2-tuple form, Sourceror-wrapped: fn {k, vals} -> {k, count(vals)} end
  defp is_count_of_vals_fn?(
         {:fn, _,
          [
            {:->, _,
             [
               [{:__block__, _, [{k_var, g_var}]}],
               {:__block__, _, [{k_var2, count_call}]}
             ]}
          ]}
       ) do
    same_var?(k_var, k_var2) and is_count_call_on?(count_call, g_var)
  end

  # 2-tuple form, raw: fn {k, vals} -> {k, count(vals)} end
  defp is_count_of_vals_fn?(
         {:fn, _,
          [
            {:->, _,
             [
               [{k_var, g_var}],
               {k_var2, count_call}
             ]}
          ]}
       ) do
    same_var?(k_var, k_var2) and is_count_call_on?(count_call, g_var)
  end

  defp is_count_of_vals_fn?(_), do: false

  # length(vals) — local call
  defp is_count_call_on?({:length, _, [{var, _, ctx}]}, {var, _, ctx})
       when is_atom(var) and is_atom(ctx),
       do: true

  # Kernel.length(vals) — remote call
  defp is_count_call_on?(
         {{:., _, [{:__aliases__, _, [:Kernel]}, :length]}, _, [{var, _, ctx}]},
         {var, _, ctx}
       )
       when is_atom(var) and is_atom(ctx),
       do: true

  # Enum.count(vals) — also counts elements
  defp is_count_call_on?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, [{var, _, ctx}]},
         {var, _, ctx}
       )
       when is_atom(var) and is_atom(ctx),
       do: true

  defp is_count_call_on?(_, _), do: false

  defp same_var?({name, _, ctx}, {name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp same_var?(_, _), do: false

  defp flatten_pipeline({:|>, _, [left, right]}),
    do: flatten_pipeline(left) ++ [right]

  defp flatten_pipeline(expr), do: [expr]

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_enum_frequencies,
      message:
        "`Enum.group_by/3` with two identity functions piped into `Enum.map/2` counting " <>
          "group sizes can be replaced with `Enum.frequencies/1`, which is clearer and " <>
          "more efficient.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
