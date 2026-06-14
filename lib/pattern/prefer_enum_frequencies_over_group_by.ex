defmodule Credence.Pattern.PreferEnumFrequenciesOverGroupBy do
  @moduledoc """
  Detects `Enum.group_by(enum, & &1) |> Map.new(fn {k, v} -> {k, length(v)} end)`
  which counts occurrences of each element — exactly what `Enum.frequencies/1` does,
  but with unnecessary intermediate per-element lists.

  The collecting step may be `Map.new/2` or the equivalent `Enum.into(%{}, ...)`
  — both build the same `%{element => count}` map, so both rewrite to
  `Enum.frequencies/1`.

  Using `Enum.group_by/2` with the identity function to count occurrences is
  unnecessarily verbose. `Enum.frequencies/1` does exactly this in one call,
  is clearer, and is optimized internally.

  ## Bad

      Enum.group_by(list, & &1) |> Map.new(fn {k, v} -> {k, length(v)} end)

      list
      |> Enum.group_by(& &1)
      |> Map.new(fn {k, v} -> {k, length(v)} end)

      Map.new(Enum.group_by(list, & &1), fn {k, v} -> {k, length(v)} end)

      list
      |> Enum.group_by(& &1)
      |> Enum.into(%{}, fn {k, v} -> {k, length(v)} end)

      Enum.into(Enum.group_by(list, & &1), %{}, fn {k, v} -> {k, length(v)} end)

  ## Good

      Enum.frequencies(list)
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

  # All pipe forms: flatten and check the last two steps
  defp check_node({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    if length(steps) >= 2 do
      [group_by_step, collect_step] = Enum.take(steps, -2)
      group_by_idx = length(steps) - 2

      if count_collect_step?(collect_step) do
        cond do
          # Piped form: Enum.group_by(key_fun) — one explicit arg
          identity_group_by_piped?(group_by_step) ->
            {{:., meta, _}, _, _} = group_by_step
            {:ok, build_issue(meta)}

          # Head-position form: Enum.group_by(enum, key_fun) — two explicit args
          # Only when it's the first step in the pipe
          group_by_idx == 0 and identity_group_by_direct?(group_by_step) ->
            {{:., meta, _}, _, _} = group_by_step
            {:ok, build_issue(meta)}

          true ->
            :error
        end
      else
        :error
      end
    else
      :error
    end
  end

  # Direct: Map.new(Enum.group_by(enum, & &1), fn {k, v} -> {k, length(v)} end)
  defp check_node({{:., meta, [{:__aliases__, _, [:Map]}, :new]}, _, [group_by_call, callback]}) do
    if identity_group_by_direct?(group_by_call) and is_length_of_group_fn?(callback) do
      {:ok, build_issue(meta)}
    else
      :error
    end
  end

  # Direct: Enum.into(Enum.group_by(enum, & &1), %{}, fn {k, v} -> {k, length(v)} end)
  defp check_node(
         {{:., meta, [{:__aliases__, _, [:Enum]}, :into]}, _,
          [group_by_call, {:%{}, _, []}, callback]}
       ) do
    if identity_group_by_direct?(group_by_call) and is_length_of_group_fn?(callback) do
      {:ok, build_issue(meta)}
    else
      :error
    end
  end

  defp check_node(_), do: :error

  # ── Fix ────────────────────────────────────────────────────────────────

  # All pipe forms: flatten and fix the last two steps
  defp fix_node({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    if length(steps) >= 2 do
      [group_by_step, collect_step] = Enum.take(steps, -2)
      group_by_idx = length(steps) - 2
      after_steps = Enum.drop(steps, group_by_idx + 2)

      if count_collect_step?(collect_step) do
        cond do
          # Piped form: Enum.group_by(key_fun) — one explicit arg
          identity_group_by_piped?(group_by_step) ->
            before_steps = Enum.take(steps, group_by_idx)
            {{:., _, _}, _, [key_fn]} = group_by_step
            enum_source = extract_enum(before_steps, [key_fn])
            build_fix(group_by_step, enum_source, after_steps)

          # Head-position form: Enum.group_by(enum, key_fun) — two explicit args
          group_by_idx == 0 and identity_group_by_direct?(group_by_step) ->
            {{:., _, _}, _, [enum, _key_fn]} = group_by_step
            build_fix(group_by_step, enum, after_steps)

          true ->
            :error
        end
      else
        :error
      end
    else
      :error
    end
  end

  # Direct: Map.new(Enum.group_by(enum, & &1), fn ...)
  defp fix_node({{:., meta, [{:__aliases__, _, [:Map]}, :new]}, _, [group_by_call, callback]}) do
    if identity_group_by_direct?(group_by_call) and is_length_of_group_fn?(callback) do
      {{:., _, _}, _, [enum, _key_fn]} = group_by_call
      {:ok, enum_frequencies(meta, enum)}
    else
      :error
    end
  end

  # Direct: Enum.into(Enum.group_by(enum, & &1), %{}, fn ...)
  defp fix_node(
         {{:., meta, [{:__aliases__, _, [:Enum]}, :into]}, _,
          [group_by_call, {:%{}, _, []}, callback]}
       ) do
    if identity_group_by_direct?(group_by_call) and is_length_of_group_fn?(callback) do
      {{:., _, _}, _, [enum, _key_fn]} = group_by_call
      {:ok, enum_frequencies(meta, enum)}
    else
      :error
    end
  end

  defp fix_node(_), do: :error

  # ── Helpers ────────────────────────────────────────────────────────────

  defp build_fix(group_by_step, enum_source, after_steps) do
    {{:., meta, _}, _, _} = group_by_step
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

  defp extract_enum([], [enum, _key_fn]), do: enum

  defp extract_enum(before_steps, [_key_fn]) do
    case before_steps do
      [single] ->
        single

      multiple ->
        Enum.reduce(tl(multiple), hd(multiple), fn step, acc ->
          {:|>, [], [acc, step]}
        end)
    end
  end

  defp extract_enum(_, _), do: nil

  # Enum.group_by(enum, & &1) — two explicit args (head-position / direct)
  defp identity_group_by_direct?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :group_by]}, _, [_enum, key_fn]}
       ) do
    identity_function?(key_fn)
  end

  defp identity_group_by_direct?(_), do: false

  # Enum.group_by(& &1) — one explicit arg (piped form)
  defp identity_group_by_piped?({{:., _, [{:__aliases__, _, [:Enum]}, :group_by]}, _, [key_fn]}) do
    identity_function?(key_fn)
  end

  defp identity_group_by_piped?(_), do: false

  # & &1 — capture of first argument
  defp identity_function?({:&, _, [{:&, _, [n]}]}) when is_integer(n), do: n == 1

  # fn x -> x end
  defp identity_function?({:fn, _, [{:->, _, [[{name, _, ctx}], {name, _, ctx}]}]})
       when is_atom(name) and is_atom(ctx),
       do: true

  defp identity_function?(_), do: false

  # Piped collecting step: `|> Map.new(fn {k, v} -> {k, length(v)} end)` or the
  # equivalent `|> Enum.into(%{}, fn {k, v} -> {k, length(v)} end)`.
  defp count_collect_step?({{:., _, [{:__aliases__, _, [:Map]}, :new]}, _, [callback]}),
    do: is_length_of_group_fn?(callback)

  defp count_collect_step?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :into]}, _, [{:%{}, _, []}, callback]}
       ),
       do: is_length_of_group_fn?(callback)

  defp count_collect_step?(_), do: false

  # Checks that the callback is of the form: fn {k, group} -> {k, length(group)} end
  # Sourceror wraps 2-tuples in {:__block__, _, [tuple]}, so we handle both
  # the wrapped and unwrapped forms.

  # 3+ element tuple form: fn {a, b, c} -> ... — uses {:{}} tag
  defp is_length_of_group_fn?(
         {:fn, _,
          [
            {:->, _,
             [
               [{:{}, _, [k_var, g_var]}],
               {:{}, _, [k_var2, length_call]}
             ]}
          ]}
       ) do
    same_var?(k_var, k_var2) and is_length_call_on?(length_call, g_var)
  end

  # 2-tuple form, Sourceror-wrapped: fn {k, group} -> {k, length(group)} end
  defp is_length_of_group_fn?(
         {:fn, _,
          [
            {:->, _,
             [
               [{:__block__, _, [{k_var, g_var}]}],
               {:__block__, _, [{k_var2, length_call}]}
             ]}
          ]}
       ) do
    same_var?(k_var, k_var2) and is_length_call_on?(length_call, g_var)
  end

  # 2-tuple form, raw: fn {k, group} -> {k, length(group)} end
  defp is_length_of_group_fn?(
         {:fn, _,
          [
            {:->, _,
             [
               [{k_var, g_var}],
               {k_var2, length_call}
             ]}
          ]}
       ) do
    same_var?(k_var, k_var2) and is_length_call_on?(length_call, g_var)
  end

  defp is_length_of_group_fn?(_), do: false

  # length(group_var) — local call
  defp is_length_call_on?({:length, _, [{var, _, ctx}]}, {var, _, ctx})
       when is_atom(var) and is_atom(ctx),
       do: true

  # Kernel.length(group_var) — remote call
  defp is_length_call_on?(
         {{:., _, [{:__aliases__, _, [:Kernel]}, :length]}, _, [{var, _, ctx}]},
         {var, _, ctx}
       )
       when is_atom(var) and is_atom(ctx),
       do: true

  # Enum.count(group_var) — also counts elements
  defp is_length_call_on?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, [{var, _, ctx}]},
         {var, _, ctx}
       )
       when is_atom(var) and is_atom(ctx),
       do: true

  defp is_length_call_on?(_, _), do: false

  defp same_var?({name, _, ctx}, {name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp same_var?(_, _), do: false

  defp flatten_pipeline({:|>, _, [left, right]}),
    do: flatten_pipeline(left) ++ [right]

  defp flatten_pipeline(expr), do: [expr]

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_enum_frequencies_over_group_by,
      message:
        "`Enum.group_by/2` with the identity function piped into `Map.new/2` counting " <>
          "group lengths can be replaced with `Enum.frequencies/1`, which is clearer and " <>
          "more efficient.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
