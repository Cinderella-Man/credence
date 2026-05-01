defmodule Credence.Rule.AvoidGraphemesEnumCount do
  @moduledoc """
  Performance rule: warns when `String.graphemes/1 |> Enum.count()` is used.

  - For `Enum.count/1` (no predicate): suggests `String.length/1`, which
    avoids allocating an intermediate list of graphemes.

  - For `Enum.count/2` (with a predicate): suggests manual binary recursion
    over the string, which avoids allocating the intermediate grapheme list
    entirely.
  """

  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # ── Pipe form: ... |> Enum.count() / ... |> Enum.count(pred) ──
        {:|>, meta, [lhs, rhs]} = node, issues ->
          cond do
            enum_count_with_arity?(rhs, 0) and immediate_graphemes?(lhs) ->
              {node, [length_issue(meta) | issues]}

            enum_count_with_arity?(rhs, 1) and immediate_graphemes?(lhs) ->
              {node, [binary_recursion_issue(meta) | issues]}

            true ->
              {node, issues}
          end

        # ── Direct form: Enum.count(String.graphemes(...)) ──
        {{:., meta, [{:__aliases__, _, [:Enum]}, :count]}, _, [arg]} = node, issues ->
          if graphemes_call?(arg) do
            {node, [length_issue(meta) | issues]}
          else
            {node, issues}
          end

        # ── Direct form: Enum.count(String.graphemes(...), pred) ──
        {{:., meta, [{:__aliases__, _, [:Enum]}, :count]}, _, [arg, _pred]} = node, issues ->
          if graphemes_call?(arg) do
            {node, [binary_recursion_issue(meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  # Detect Enum.count with a specific number of explicit args
  # In a pipe, Enum.count() has 0 args, Enum.count(pred) has 1 arg.
  defp enum_count_with_arity?({{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, args}, arity)
       when is_list(args),
       do: length(args) == arity

  defp enum_count_with_arity?(_, _), do: false

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

  # ── Issue builders ──────────────────────────────────────────────────

  defp length_issue(meta) do
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

  defp binary_recursion_issue(meta) do
    %Issue{
      rule: :avoid_graphemes_enum_count,
      severity: :warning,
      message: """
      Avoid `String.graphemes/1 |> Enum.count/2` — it allocates an
      intermediate list of all graphemes just to count the ones that
      match the predicate.

      Instead, recurse over the binary directly using
      `String.next_grapheme/1`:

          defp count_matching(string, pred, acc \\\\ 0) do
            case String.next_grapheme(string) do
              {grapheme, rest} ->
                count_matching(rest, pred, if(pred.(grapheme), do: acc + 1, else: acc))

              nil ->
                acc
            end
          end

      This avoids building the grapheme list entirely and counts in a
      single pass with constant memory overhead.
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
