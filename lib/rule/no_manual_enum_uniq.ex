defmodule Credence.Rule.NoManualEnumUniq do
  @moduledoc """
  Performance and idiomatic code rule: warns when `Enum.uniq/1` is manually
  reimplemented using `Enum.reduce/3` and `MapSet`.

  Lists are deduplicated most efficiently using the built-in `Enum.uniq/1`
  or `Enum.uniq_by/2`, which are implemented natively.
  """

  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Matches Enum.reduce(list, {MapSet.new(), []}, fn ...)
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, [_list, init_acc, fun]} = node,
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

  # ------------------------------------------------------------
  # PATTERN MATCHING LOGIC
  # ------------------------------------------------------------

  defp manual_uniq?(init_acc, fun) do
    # 1. Find which index (0 or 1) in the tuple contains the MapSet.new()
    case find_mapset_index(init_acc) do
      nil ->
        false

      index ->
        # 2. Check if the lambda uses that index specifically to deduplicate the item
        matches_dedup_lambda?(fun, index)
    end
  end

  # Detects {MapSet.new(), ...} (index 0) or {..., MapSet.new()} (index 1)
  defp find_mapset_index({e1, e2}) do
    cond do
      mapset_init?(e1) -> 0
      mapset_init?(e2) -> 1
      true -> nil
    end
  end

  defp find_mapset_index(_), do: nil

  defp mapset_init?({{:., _, [{:__aliases__, _, [:MapSet]}, :new]}, _, _}), do: true
  defp mapset_init?(_), do: false

  defp matches_dedup_lambda?({:fn, _, clauses}, ms_index) do
    Enum.any?(clauses, fn
      {:->, _, [[item_pattern, acc_pattern], body]} ->
        item_var = get_var_name(item_pattern)
        seen_var = get_var_name_at_index(acc_pattern, ms_index)

        if item_var && seen_var do
          is_conditional_dedup?(body, seen_var, item_var)
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

  defp get_var_name_at_index({left, right}, index) do
    target = if index == 0, do: left, else: right
    get_var_name(target)
  end

  defp get_var_name_at_index(_, _), do: nil

  # Scans the function body for a conditional (if/unless/case)
  # that is powered by MapSet.member?(seen_var, item_var)
  defp is_conditional_dedup?(body, seen_var, item_var) do
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
      # Match: MapSet.member?(seen, item)
      {{:., _, [{:__aliases__, _, [:MapSet]}, :member?]}, _,
       [{^seen_var, _, nil}, {^item_var, _, nil}]} ->
        true

      # Match: !MapSet.member?(...) or not MapSet.member?(...)
      {op, _, [inner]} when op in [:!, :not] ->
        uses_mapset_member?(inner, seen_var, item_var)

      _ ->
        false
    end
  end

  # ------------------------------------------------------------
  # ISSUE DATA
  # ------------------------------------------------------------

  defp trigger_issue(meta) do
    %Issue{
      rule: :no_manual_enum_uniq,
      severity: :warning,
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
