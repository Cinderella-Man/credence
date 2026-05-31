defmodule Credence.Pattern.NoManualEnumUniq do
  @moduledoc """
  Performance and idiomatic code rule: warns when `Enum.uniq/1` is manually
  reimplemented using `Enum.reduce/3` and a set (`MapSet` or a plain `%{}`
  map used as a set via `Map.has_key?`/`Map.put(_, _, true)`).

  Lists are deduplicated most efficiently using the built-in `Enum.uniq/1`
  or `Enum.uniq_by/2`, which are implemented natively.

  The fix also strips orphaned pipeline steps that were part of the manual
  pattern — specifically `|> elem(0)` / `|> elem(1)` (which extracted the
  list from the `{list, set}` accumulator) and `|> Enum.reverse()` (which
  reversed the prepended list). Since `Enum.uniq/1` returns a plain list in
  insertion order, both steps become unnecessary after the replacement.

  ## Bad

      Enum.reduce(list, {MapSet.new(), []}, fn item, {seen, acc} ->
        if MapSet.member?(seen, item) do
          {seen, acc}
        else
          {MapSet.put(seen, item), [item | acc]}
        end
      end)

      # same pattern with a plain map used as a set:
      Enum.reduce(list, {[], %{}}, fn item, {acc, seen} ->
        if Map.has_key?(seen, item) do
          {acc, seen}
        else
          {acc ++ [item], Map.put(seen, item, true)}
        end
      end)
      |> elem(0)

      # or in a pipeline with downstream tuple extraction:
      list
      |> Enum.reduce({[], MapSet.new()}, fn x, {results, tracked} ->
        unless MapSet.member?(tracked, x) do
          {[x | results], MapSet.put(tracked, x)}
        else
          {results, tracked}
        end
      end)
      |> elem(0)
      |> Enum.reverse()

  ## Good

      Enum.uniq(list)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, [_list, init_acc, fun]} = node,
        issues ->
          if manual_uniq?(init_acc, fun) do
            {node, [trigger_issue(meta) | issues]}
          else
            {node, issues}
          end

        {:|>, meta, [_, {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [init_acc, fun]}]} =
            node,
        issues ->
          if manual_uniq?(init_acc, fun) do
            {node, [trigger_issue(meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  #
  # Uses Macro.postwalk so transformations compose bottom-up:
  #
  #   1. Replace manual-uniq reduce with Enum.uniq (tagged with marker)
  #   2. Strip orphaned |> elem(N) when left ends with tagged Enum.uniq
  #   3. Strip orphaned |> Enum.reverse() when left ends with tagged Enum.uniq
  #
  # The marker prevents stripping legitimate elem/reverse calls that
  # happen to follow a pre-existing Enum.uniq in the original source.

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, &apply_uniq_fix/1)
  end

  defp apply_uniq_fix(node) do
    case node do
      # Enum.reduce(list, {MapSet.new(), []}, fn ...) → Enum.uniq(list)
      {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, :reduce]}, call_meta,
       [list_arg, init_acc, fun]} ->
        if manual_uniq?(init_acc, fun) do
          {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, :uniq]},
           tag_fresh_uniq(call_meta), [list_arg]}
        else
          node
        end

      # ... |> Enum.reduce({MapSet, []}, fn ...) → ... |> Enum.uniq()
      {:|>, pipe_meta,
       [
         left,
         {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, :reduce]}, call_meta,
          [init_acc, fun]}
       ]} ->
        if manual_uniq?(init_acc, fun) do
          uniq_call =
            {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, :uniq]},
             tag_fresh_uniq(call_meta), []}

          {:|>, pipe_meta, [left, uniq_call]}
        else
          node
        end

      # ... |> Enum.uniq() |> elem(N) → ... |> Enum.uniq()
      {:|>, _pipe_meta, [left, {:elem, _, _}]} ->
        if ends_with_fresh_uniq?(left), do: left, else: node

      # elem(Enum.uniq(list), N) → Enum.uniq(list)
      {:elem, _, [inner, _index]} ->
        if fresh_uniq_call?(inner), do: inner, else: node

      # ... |> Enum.uniq() |> Enum.reverse() → ... |> Enum.uniq()
      {:|>, _pipe_meta, [left, {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, []}]} ->
        if ends_with_fresh_uniq?(left), do: left, else: node

      # Enum.reverse(Enum.uniq(list)) → Enum.uniq(list)
      {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, [inner]} ->
        if fresh_uniq_call?(inner), do: inner, else: node

      # {var, _} = Enum.uniq(list); Enum.reverse(var) → Enum.uniq(list)
      {:__block__, _block_meta, stmts} when length(stmts) >= 2 ->
        case fix_uniq_tuple_block(stmts) do
          nil -> node
          single_node -> single_node
        end

      other ->
        other
    end
  end

  defp tag_fresh_uniq(meta) when is_list(meta) do
    [{:__credence_fresh_uniq__, true} | meta]
  end

  defp tag_fresh_uniq(_), do: [__credence_fresh_uniq__: true]

  defp fresh_uniq_call?({{:., _, [{:__aliases__, _, [:Enum]}, :uniq]}, meta, _})
       when is_list(meta) do
    List.keymember?(meta, :__credence_fresh_uniq__, 0)
  end

  defp fresh_uniq_call?(_), do: false

  defp ends_with_fresh_uniq?({:|>, _, [_, right]}), do: fresh_uniq_call?(right)
  defp ends_with_fresh_uniq?(node), do: fresh_uniq_call?(node)

  defp reverse_of_var?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, [{var_name, _, nil}]},
         {var_name, _, nil}
       ),
       do: true

  defp reverse_of_var?(
         {:|>, _, [{var_name, _, nil}, {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, []}]},
         {var_name, _, nil}
       ),
       do: true

  defp reverse_of_var?(_, _), do: false

  defp strip_fresh_tag({{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, :uniq]}, meta, args}) do
    clean_meta = Keyword.delete(meta, :__credence_fresh_uniq__)
    {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, :uniq]}, clean_meta, args}
  end

  # Looks for {var, _} = tagged_uniq / {_, var} = tagged_uniq followed by
  # Enum.reverse(var), and collapses both into just the untagged Enum.uniq call.
  defp fix_uniq_tuple_block(stmts) do
    Enum.with_index(stmts)
    |> Enum.find_value(fn {stmt, idx} ->
      with {:ok, var, tagged} <- extract_uniq_tuple_assign(stmt) do
        if fresh_uniq_call?(tagged),
          do: remove_reverse_and_replace(stmts, idx, var, tagged)
      end
    end)
  end

  # Standard 3-tuple form: {var, _} = tagged
  defp extract_uniq_tuple_assign({:=, _, [{:{}, _, [var, {:_, _, nil}]}, tagged]}),
    do: {:ok, var, tagged}

  # Standard 3-tuple form: {_, var} = tagged
  defp extract_uniq_tuple_assign({:=, _, [{:{}, _, [{:_, _, nil}, var]}, tagged]}),
    do: {:ok, var, tagged}

  # Sourceror 2-tuple wrapper: {var, _} = tagged
  defp extract_uniq_tuple_assign({:=, _, [{:__block__, _, [{var, {:_, _, nil}}]}, tagged]}),
    do: {:ok, var, tagged}

  # Sourceror 2-tuple wrapper: {_, var} = tagged
  defp extract_uniq_tuple_assign({:=, _, [{:__block__, _, [{{:_, _, nil}, var}]}, tagged]}),
    do: {:ok, var, tagged}

  defp extract_uniq_tuple_assign(_), do: nil

  defp remove_reverse_and_replace(stmts, assign_idx, var, tagged) do
    Enum.with_index(stmts)
    |> Enum.find_value(fn {s, idx} ->
      if idx != assign_idx && reverse_of_var?(s, var) do
        untagged = strip_fresh_tag(tagged)
        stmts
        |> List.replace_at(assign_idx, untagged)
        |> List.delete_at(idx)
        |> case do
          [single] -> single
          multiple -> {:__block__, [], multiple}
        end
      end
    end)
  end

  defp manual_uniq?(init_acc, fun) do
    case find_mapset_index(init_acc) do
      nil -> false
      index -> matches_dedup_lambda?(fun, index)
    end
  end

  # Sourceror wraps 2-tuples in {:__block__, meta, [{a, b}]}
  defp find_mapset_index({:__block__, _, [{e1, e2}]}) do
    find_mapset_index({e1, e2})
  end

  defp find_mapset_index({e1, e2}) do
    cond do
      mapset_init?(e1) -> 0
      mapset_init?(e2) -> 1
      true -> nil
    end
  end

  defp find_mapset_index(_), do: nil

  defp mapset_init?({{:., _, [{:__aliases__, _, [:MapSet]}, :new]}, _, _}), do: true
  # Plain map used as a set: %{ }
  defp mapset_init?({:%{}, _, []}), do: true
  defp mapset_init?(_), do: false

  defp matches_dedup_lambda?({:fn, _, clauses}, ms_index) do
    Enum.any?(clauses, fn
      {:->, _, [[item_pattern, acc_pattern], body]} ->
        item_var = get_var_name(item_pattern)
        seen_var = get_var_name_at_index(acc_pattern, ms_index)

        if item_var && seen_var do
          conditional_dedup?(body, seen_var, item_var)
        else
          false
        end

      _ ->
        false
    end)
  end

  defp matches_dedup_lambda?(_, _), do: false

  defp get_var_name({name, _, nil}) when is_atom(name), do: name
  defp get_var_name(_), do: nil

  # Sourceror wraps 2-tuples in {:__block__, meta, [{a, b}]}
  defp get_var_name_at_index({:__block__, _, [{left, right}]}, index) do
    get_var_name_at_index({left, right}, index)
  end

  defp get_var_name_at_index({left, right}, index) do
    target = if index == 0, do: left, else: right
    get_var_name(target)
  end

  defp get_var_name_at_index(_, _), do: nil

  defp conditional_dedup?(body, seen_var, item_var) do
    {_, found?} =
      Macro.prewalk(body, false, fn
        {type, _, [condition | _]} = node, acc when type in [:if, :unless, :case] ->
          if uses_mapset_member?(condition, seen_var, item_var) do
            {node, true}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    found?
  end

  defp uses_mapset_member?(condition, seen_var, item_var) do
    case condition do
      {{:., _, [{:__aliases__, _, [:MapSet]}, :member?]}, _,
       [{^seen_var, _, nil}, {^item_var, _, nil}]} ->
        true

      # Map.has_key?(seen, item) — plain map used as a set
      {{:., _, [{:__aliases__, _, [:Map]}, :has_key?]}, _,
       [{^seen_var, _, nil}, {^item_var, _, nil}]} ->
        true

      {op, _, [inner]} when op in [:!, :not] ->
        uses_mapset_member?(inner, seen_var, item_var)

      _ ->
        false
    end
  end

  defp trigger_issue(meta) do
    %Issue{
      rule: :no_manual_enum_uniq,
      message: """
      Manual reimplementation of `Enum.uniq/1` detected.
      This pattern uses `Enum.reduce/3` with a `MapSet` to filter duplicates.
      This is significantly more verbose and less efficient than the built-in
      function.
      Consider using:
        Enum.uniq(list)
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
