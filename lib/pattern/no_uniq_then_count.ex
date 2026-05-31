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

  ## Flagged patterns

  `Enum.uniq()` piped into `length/1` or `Enum.count/1`.
  Also detects `Enum.uniq(fn)` with a transform function.

  ## Not flagged

  - `Enum.uniq()` alone (without count/length following)
  - `Enum.uniq |> Enum.map(...)` (uniq used for further processing)
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
  def fix_patches(_ast, _opts), do: []

  # Pipeline: ... |> Enum.uniq() |> length()
  # Pipeline: ... |> Enum.uniq() |> Enum.count()
  defp check_node({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(fn [first, second] ->
      if uniq_step?(first) and count_step?(second) do
        {:ok, build_issue(first)}
      else
        nil
      end
    end)
    |> case do
      {:ok, _} = result -> result
      _ -> :error
    end
  end

  defp check_node(_), do: :error

  defp uniq_step?({{:., _, [mod, :uniq]}, _, args})
       when is_list(args) and length(args) in [0, 1],
       do: enum_module?(mod)

  defp uniq_step?(_), do: false

  # length/1 in pipeline context is called as length() with 0 explicit args
  defp count_step?({:length, _, args}) when is_list(args) and length(args) in [0, 1], do: true
  # Enum.count/2 (with predicate) is a different operation — only flag Enum.count/1
  defp count_step?({{:., _, [mod, :count]}, _, []}), do: enum_module?(mod)
  defp count_step?(_), do: false

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?(_), do: false

  defp flatten_pipeline({:|>, _, [left, right]}),
    do: flatten_pipeline(left) ++ [right]

  defp flatten_pipeline(expr), do: [expr]

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
