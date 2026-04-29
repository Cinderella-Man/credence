defmodule Credence.Rule.NoManualEnumUniq do
  @moduledoc """
  Detects manual reimplementation of Enum.uniq/1 or Enum.uniq_by/2
  using Enum.reduce/3 + MapSet in a deduplication pattern.

  This version avoids false positives by requiring a strict structural
  pattern: MapSet-based "seen + accumulator list" tuple reduction.
  """

  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, [_list, init_acc, fun]} = node,
        issues ->
          if uniq_like_reduce?(init_acc, fun) do
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
  # STRICT STRUCTURAL DETECTION
  # ------------------------------------------------------------

  defp uniq_like_reduce?(init_acc, fun) do
    match_seen_acc_tuple?(init_acc) and matches_dedup_lambda?(fun)
  end

  # FIX: 2-element tuples in AST are just `{elem1, elem2}`.
  # We check both positions to support {MapSet.new(), []} or {[], MapSet.new()}
  defp match_seen_acc_tuple?({elem1, elem2}) do
    mapset_init?(elem1) or mapset_init?(elem2)
  end
  defp match_seen_acc_tuple?(_), do: false

  defp mapset_init?({{:., _, [{:__aliases__, _, [:MapSet]}, :new]}, _, _}), do: true
  defp mapset_init?(_), do: false

  # ------------------------------------------------------------
  # DETECT TRUE "ENUM.UNIQ REIMPLEMENTATION" LAMBDA
  # ------------------------------------------------------------

  defp matches_dedup_lambda?({:fn, _, clauses}) do
    Enum.any?(clauses, &match_dedup_clause?/1)
  end
  defp matches_dedup_lambda?(_), do: false

  defp match_dedup_clause?({:->, _, [[_item, acc_arg], body]}) do
    # Acc arg should be a 2-tuple pattern (like `{seen, acc}` or `{acc, seen}`)
    is_2_tuple_pattern?(acc_arg) and uses_mapset_dedup?(body)
  end
  defp match_dedup_clause?(_), do: false

  defp is_2_tuple_pattern?({_, _}), do: true
  defp is_2_tuple_pattern?(_), do: false

  # FIX: Removed `^seen_var` pinning. Searching the body for the presence
  # of `member?` and `put` inside a 2-tuple reduction is highly accurate.
  defp uses_mapset_dedup?(body) do
    has_member =
      Macro.prewalk(body, false, fn
        {{:., _, [{:__aliases__, _, [:MapSet]}, :member?]}, _, _} = node, _ -> {node, true}
        node, acc -> {node, acc}
      end) |> elem(1)

    has_put =
      Macro.prewalk(body, false, fn
        {{:., _, [{:__aliases__, _, [:MapSet]}, :put]}, _, _} = node, _ -> {node, true}
        node, acc -> {node, acc}
      end) |> elem(1)

    has_member and has_put
  end

  # ------------------------------------------------------------
  # ISSUE
  # ------------------------------------------------------------

  defp trigger_issue(meta) do
    %Issue{
      rule: :no_manual_enum_uniq,
      severity: :warning,
      message: """
      Manual reimplementation of Enum.uniq/1 detected.

      This pattern uses Enum.reduce/3 with a MapSet "seen" accumulator
      and a filtered list accumulator, which is equivalent to Enum.uniq/1
      but significantly more verbose.

      Prefer:
        Enum.uniq(list)
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
