defmodule Credence.Rule.AvoidGraphemesEnumCount do
  @moduledoc """
  Performance rule: warns when `String.graphemes/1 |> Enum.count()` is used.

  `String.length/1` is more efficient because it avoids allocating an
  intermediate list of graphemes.
  """

  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Match: ... |> Enum.count()
        {:|>, meta, [lhs, rhs]} = node, issues ->
          if enum_count_call?(rhs) and immediate_graphemes?(lhs) do
            {node, [trigger_issue(meta) | issues]}
          else
            {node, issues}
          end

        # Match: Enum.count(String.graphemes(...))
        {{:., meta, [{:__aliases__, _, [:Enum]}, :count]}, _, [arg]} = node, issues ->
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

  # Detect Enum.count/1 (both direct and zero-arity pipe form)
  defp enum_count_call?({{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, args})
       when is_list(args),
       do: true

  defp enum_count_call?(_), do: false

  # Ensure graphemes is the immediate previous pipeline step
  defp immediate_graphemes?({:|>, _, [_, rhs]}),
    do: graphemes_call?(rhs)

  defp immediate_graphemes?(other),
    do: graphemes_call?(other)

  # Match String.graphemes/1
  defp graphemes_call?({{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, args})
       when is_list(args),
       do: true

  defp graphemes_call?(_), do: false

  defp trigger_issue(meta) do
    %Issue{
      rule: :avoid_graphemes_enum_count,
      severity: :warning,
      message: """
      Use `String.length/1` instead of `Enum.count(String.graphemes(...))`.

      Counting graphemes via `Enum.count/1` forces allocation of an
      intermediate list, while `String.length/1` avoids this.
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
