defmodule Credence.Pattern.NoUniqThenCount do
  @moduledoc """
  Detects `Enum.uniq/1` piped into `length/1` or `Enum.count/1`, which
  creates an unnecessary intermediate list only to count its size.

  ## Why this matters

  LLMs frequently produce `Enum.uniq |> length()` pipelines to count
  distinct elements. This allocates an intermediate list that is
  immediately consumed by a linear scan:

      # Flagged — intermediate list from uniq
      items |> Enum.uniq() |> length()
      items |> Enum.uniq() |> Enum.count()

      # Better — MapSet deduplicates on insertion, no intermediate list
      items |> MapSet.new() |> MapSet.size()

  `MapSet.new/1` builds the set in a single pass, and `MapSet.size/1`
  returns the count in O(1).

  ## Why the rewrite is exact

  `Enum.uniq/1` and `MapSet` both deduplicate using map-key (exact,
  `===`) equality — `1` and `1.0` stay distinct under both, `+0.0` and
  `-0.0` stay distinct under both. The number of distinct elements is
  therefore identical, and `length/1`/`Enum.count/1` and `MapSet.size/1`
  all return that cardinality. The source enumerable is evaluated exactly
  once on the left of the pipe in both forms.

  ## Flagged patterns

  `Enum.uniq()` piped into `length/1` or `Enum.count/1`, in two forms:

  - piped uniq: `enum |> Enum.uniq() |> length()`
  - head uniq:  `Enum.uniq(enum) |> Enum.count()`

  ## Not flagged

  - `Enum.uniq()` alone (without count/length following)
  - `Enum.uniq |> Enum.map(...)` (uniq used for further processing)
  - `Enum.uniq |> Enum.count(predicate)` (a filtered count, different op)

  ## Bad

      defmodule BadNUTC do
        def count_unique(items) do
          Enum.uniq(items) |> Enum.count()
        end
      end

  ## Good

      defmodule BadNUTC do
        def count_unique(items) do
          MapSet.new(items) |> MapSet.size()
        end
      end
  """

  use Credence.Pattern.Rule

  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case match_pipeline(node) do
          {:ok, _mode, uniq_node} -> {node, [build_issue(uniq_node) | issues]}
          :no -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {:|>, _, [_, _]} = node ->
        case match_pipeline(node) do
          {:ok, mode, _uniq_node} -> rewrite(node, mode)
          :no -> node
        end

      node ->
        node
    end)
  end

  #
  # A pipeline node `left |> right` is a match when `right` is the count
  # step (`length()` / `Enum.count()`) and the step immediately before it
  # is `Enum.uniq`. Examining only the top adjacent pair of each `|>` node
  # visits every consecutive step-pair exactly once, so a flagged pipeline
  # produces exactly one issue (no double-counting when more steps follow).
  #
  # `:head`  — uniq is the pipeline head: `Enum.uniq(enum) |> count`.
  # `:piped` — uniq is a piped step:      `... |> Enum.uniq() |> count`.

  defp match_pipeline({:|>, _, [left, right]}) do
    if count_step?(right) do
      uniq_in_left(left)
    else
      :no
    end
  end

  defp match_pipeline(_), do: :no

  # Head form: the uniq call carries its source as its single argument.
  defp uniq_in_left({{:., _, [mod, :uniq]}, _, [_arg]} = node) do
    if enum_module?(mod), do: {:ok, :head, node}, else: :no
  end

  # Piped form: the previous step is a zero-arg `|> Enum.uniq()`.
  defp uniq_in_left({:|>, _, [_, {{:., _, [mod, :uniq]}, _, []} = node]}) do
    if enum_module?(mod), do: {:ok, :piped, node}, else: :no
  end

  defp uniq_in_left(_), do: :no

  # `length()` in pipeline position is called with zero explicit args.
  defp count_step?({:length, _, []}), do: true
  # `Enum.count/1` only — `Enum.count(pred)` is a filtered count, excluded.
  defp count_step?({{:., _, [mod, :count]}, _, []}), do: enum_module?(mod)
  defp count_step?(_), do: false

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?(_), do: false

  # `Enum.uniq(enum) |> count` → `MapSet.new(enum) |> MapSet.size()`
  defp rewrite({:|>, _, [left, _right]}, :head) do
    {{:., _, [_, :uniq]}, _, [arg]} = left
    pipe(mapset_call(:new, [arg]), pipe_tail(:size))
  end

  # `pre |> Enum.uniq() |> count` → `pre |> MapSet.new() |> MapSet.size()`
  defp rewrite({:|>, _, [left, _right]}, :piped) do
    {:|>, _, [prefix, _uniq]} = left
    pipe(pipe(prefix, mapset_call(:new, [])), pipe_tail(:size))
  end

  defp pipe(left, right), do: {:|>, [], [left, right]}

  defp pipe_tail(fun), do: mapset_call(fun, [])

  defp mapset_call(fun, args),
    do: {{:., [], [{:__aliases__, [], [:MapSet]}, fun]}, [], args}

  defp build_issue(uniq_node) do
    {{:., meta, [_, :uniq]}, _, _} = uniq_node

    %Issue{
      rule: :no_uniq_then_count,
      message: message(),
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp message do
    "`Enum.uniq/1` piped into `length/1` or `Enum.count/1` creates an " <>
      "unnecessary intermediate list. Use `MapSet.new(enum) |> MapSet.size()` " <>
      "instead — it deduplicates in a single pass with O(1) size lookup."
  end
end
