defmodule Credence.Rule.NoTakeWhileLengthCheck do
  @moduledoc """
  Detects `Enum.take_while/2` piped into `length/1` or `Enum.count/1`,
  which materializes an intermediate list only to count it.

  ## Why this matters

  LLMs generate this pattern when they think procedurally: "keep going
  while the condition holds, then check how far I got."  The idiomatic
  Elixir approach depends on intent:

      # Flagged — materializes a list just to count it
      0..(half - 1)
      |> Enum.take_while(fn i ->
        Enum.at(graphemes, start + i) == Enum.at(graphemes, start + len - 1 - i)
      end)
      |> length() == half

      # If checking "did all pass?" → use Enum.all?/2
      Enum.all?(0..(half - 1), fn i -> ... end)

      # If counting consecutive matches → use Enum.reduce_while/3
      Enum.reduce_while(range, 0, fn i, count ->
        if condition, do: {:cont, count + 1}, else: {:halt, count}
      end)

  `Enum.take_while |> length` always allocates a throwaway list.
  `Enum.all?` and `Enum.reduce_while` do not.

  ## Flagged patterns

  - `Enum.take_while(enum, fun) |> length()`
  - `Enum.take_while(enum, fun) |> Enum.count()`
  - `length(Enum.take_while(enum, fun))`
  - `Enum.count(Enum.take_while(enum, fun))`
  - `enum |> Enum.take_while(fun) |> length()`
  """

  @behaviour Credence.Rule
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

  # ------------------------------------------------------------
  # NODE MATCHING
  # ------------------------------------------------------------

  # Pipeline form: ... |> Enum.take_while(fn) |> length()
  #            or: ... |> Enum.take_while(fn) |> Enum.count()
  defp check_node({:|>, meta, _} = node) do
    pipeline = flatten_pipeline(node)
    check_pipeline(pipeline, meta)
  end

  # Direct call: length(Enum.take_while(enum, fun))
  defp check_node({:length, meta, [inner]}) do
    if take_while_call?(inner) do
      {:ok, build_issue(meta)}
    else
      :error
    end
  end

  # Direct call: Enum.count(Enum.take_while(enum, fun))
  defp check_node({{:., meta, [mod, :count]}, _, [inner]}) do
    if enum_module?(mod) and take_while_call?(inner) do
      {:ok, build_issue(meta)}
    else
      :error
    end
  end

  defp check_node(_), do: :error

  # ------------------------------------------------------------
  # PIPELINE ANALYSIS
  # ------------------------------------------------------------

  defp check_pipeline(steps, meta) do
    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(fn [first, second] ->
      take_while_step?(first) and length_step?(second)
    end)
    |> then(fn
      true -> {:ok, build_issue(meta)}
      false -> :error
    end)
  end

  # ------------------------------------------------------------
  # STEP DETECTION
  # ------------------------------------------------------------

  # Enum.take_while(enum, fun) — full call
  defp take_while_call?({{:., _, [mod, :take_while]}, _, args})
       when is_list(args) and length(args) == 2 do
    enum_module?(mod)
  end

  defp take_while_call?(_), do: false

  # Enum.take_while(fun) — pipeline form (1 explicit arg)
  defp take_while_step?({{:., _, [mod, :take_while]}, _, args})
       when is_list(args) do
    enum_module?(mod)
  end

  defp take_while_step?(_), do: false

  # length() — pipeline form (0 explicit args)
  defp length_step?({:length, _, []}), do: true

  # Enum.count() — pipeline form (0 explicit args)
  defp length_step?({{:., _, [mod, :count]}, _, []}) do
    enum_module?(mod)
  end

  defp length_step?(_), do: false

  # ------------------------------------------------------------
  # HELPERS
  # ------------------------------------------------------------

  defp flatten_pipeline({:|>, _, [left, right]}) do
    flatten_pipeline(left) ++ [right]
  end

  defp flatten_pipeline(expr), do: [expr]

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?(_), do: false

  # ------------------------------------------------------------
  # MESSAGE GENERATION
  # ------------------------------------------------------------

  defp build_issue(meta) do
    %Issue{
      rule: :no_take_while_length_check,
      message: build_message(),
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp build_message do
    """
    `Enum.take_while/2` piped into `length/1` allocates an intermediate \
    list just to count it.

    If checking whether all elements pass the condition:

        Enum.all?(enumerable, predicate)

    If counting consecutive matches from the start:

        Enum.reduce_while(enumerable, 0, fn elem, count ->
          if condition, do: {:cont, count + 1}, else: {:halt, count}
        end)
    """
  end
end
