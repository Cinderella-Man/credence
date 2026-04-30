defmodule Credence.Rule.AvoidGraphemesLength do
  @moduledoc """
  Performance rule: warns when `String.graphemes/1 |> length()` is used.

  `String.length/1` is significantly more efficient. `String.graphemes/1`
  allocates a list of all graphemes in memory, which is then traversed by
  `length/1` and immediately garbage collected.

  `String.length/1` avoids building this intermediate list.
  """

  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Match: ... |> length()
        {:|>, meta, [lhs, {:length, _, _}]} = node, issues ->
          if immediate_graphemes?(lhs) do
            {node, [trigger_issue(meta) | issues]}
          else
            {node, issues}
          end

        # Match: length(String.graphemes(...))
        {:length, meta, [arg]} = node, issues ->
          if graphemes_call?(arg) do
            {node, [trigger_issue(meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  # Ensure graphemes is the immediate previous pipeline step
  defp immediate_graphemes?({:|>, _, [_, rhs]}),
    do: graphemes_call?(rhs)

  defp immediate_graphemes?(other),
    do: graphemes_call?(other)

  # Relaxed match for String.graphemes/1
  defp graphemes_call?({{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, args})
       when is_list(args),
       do: true

  defp graphemes_call?(_), do: false

  defp trigger_issue(meta) do
    %Issue{
      rule: :avoid_graphemes_length,
      severity: :warning,
      message: """
      Use `String.length/1` instead of counting `String.graphemes/1`.

      `String.graphemes/1` builds an intermediate list that is immediately
      discarded, while `String.length/1` avoids this allocation.
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
