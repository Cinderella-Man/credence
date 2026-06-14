defmodule Credence.Pattern.PreferGraphemesForCharacterUniqueness do
  @moduledoc """
  Readability & correctness rule: Detects the pattern
  `String.to_charlist(s) |> Enum.uniq() |> Enum.count() |> (&(&1 == String.length(s))).()`.

  `String.to_charlist/1` decomposes into **codepoints** (integers), while
  `String.length/1` counts **graphemes** (whole characters). For decomposed
  Unicode (e.g. `"é"` = `"e"` + U+0301) these differ — the codepoint count is
  higher than the grapheme count — so the comparison is wrong. Using
  `String.graphemes/1` instead keeps both sides grapheme-level.

  Under the `single_codepoint_graphemes` assumption (every grapheme is exactly
  one codepoint), the two decompositions agree, so the rewrite is safe.

  The fix also modernises the capture call idiom from `(&expr).()` to
  `then(&expr)`, which reads more naturally in a pipeline.

  ## Bad (only rewritten while `single_codepoint_graphemes` is on)

      String.to_charlist(s) |> Enum.uniq() |> Enum.count() |> (&(&1 == String.length(s))).()

  ## Good

      String.graphemes(s) |> Enum.uniq() |> Enum.count() |> then(&(&1 == String.length(s)))
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def assumptions, do: [:single_codepoint_graphemes]

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Full pipeline: ... |> Enum.count() |> (&(&1 == String.length(var))).()
        {:|>, meta, [left, capture_invocation]} = node, issues ->
          if immediate_capture_invocation?(capture_invocation) and
               enum_count_step?(rightmost_pipe_end(left)) do
            # Walk the pipeline to find String.to_charlist
            if pipeline_has_to_charlist?(left) do
              {node, [build_issue(meta) | issues]}
            else
              {node, issues}
            end
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    _opts = opts

    {_ast, patches} =
      Macro.prewalk(ast, [], fn
        # Full pipeline: Enum.count() |> (&(&1 == String.length(var))).()
        {:|>, pipe_meta, [left, capture_invocation]} = node, patches ->
          case capture_invocation do
            # Match the capture invocation pattern: (&expr).()
            {{:., _, [capture_expr = {:&, _, [{:==, _, _}]}]}, _, []} ->
              if enum_count_step?(rightmost_pipe_end(left)) do
                case find_and_replace_charlist(left) do
                  {:ok, new_left} ->
                    # Build the replacement string
                    # The capture expr has the comparison, render it
                    clean_capture = strip_parens_meta(capture_expr)
                    then_call = {:then, [], [clean_capture]}
                    new_pipe = {:|>, pipe_meta, [new_left, then_call]}
                    rendered = Sourceror.to_string(new_pipe)

                    # Build patch covering from the | > to end of invocation
                    pipe_range = Sourceror.get_range(node)

                    case pipe_range do
                      %Sourceror.Range{} = range ->
                        patch = %{range: range, change: rendered}
                        {node, [patch | patches]}

                      _ ->
                        {node, patches}
                    end

                  :error ->
                    {node, patches}
                end
              else
                {node, patches}
              end

            _ ->
              {node, patches}
          end

        node, patches ->
          {node, patches}
      end)

    Enum.reverse(patches)
  end

  # Strip parens and closing metadata from AST nodes to avoid rendering issues
  defp strip_parens_meta(ast) do
    Macro.prewalk(ast, fn
      {form, meta, args} ->
        {form, Keyword.drop(meta, [:parens, :closing, :line, :column, :last, :end]), args}

      other ->
        other
    end)
  end

  # Check if a node is an immediate invocation of a capture: (&expr).()
  defp immediate_capture_invocation?({{:., _, [{:&, _, [{:==, _, _}]}]}, _, []}),
    do: true

  defp immediate_capture_invocation?(_), do: false

  # Check if a node is a String.to_charlist call
  defp to_charlist_call?({{:., _, [{:__aliases__, _, [:String]}, :to_charlist]}, _, _}),
    do: true

  defp to_charlist_call?(_), do: false

  # Check if a node is an Enum.count() call (no arguments)
  defp enum_count_step?({{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, []}), do: true
  defp enum_count_step?(_), do: false

  # Get the rightmost element of a pipe chain (the last step before current)
  defp rightmost_pipe_end({:|>, _, [_, right]}), do: right
  defp rightmost_pipe_end(other), do: other

  # Check if the pipeline contains a String.to_charlist call
  defp pipeline_has_to_charlist?({:|>, _, [left, right]}) do
    to_charlist_call?(left) or to_charlist_call?(right) or pipeline_has_to_charlist?(left)
  end

  defp pipeline_has_to_charlist?(node), do: to_charlist_call?(node)

  # Find and replace String.to_charlist with String.graphemes in the pipe chain
  defp find_and_replace_charlist({:|>, meta, [left, right]}) do
    case find_and_replace_charlist(left) do
      {:ok, new_left} ->
        {:ok, {:|>, meta, [new_left, right]}}

      :error ->
        case find_and_replace_charlist(right) do
          {:ok, new_right} -> {:ok, {:|>, meta, [left, new_right]}}
          :error -> :error
        end
    end
  end

  defp find_and_replace_charlist(
         {{:., call_meta, [{:__aliases__, alias_meta, [:String]}, :to_charlist]}, fun_meta, args}
       ) do
    {:ok, {{:., call_meta, [{:__aliases__, alias_meta, [:String]}, :graphemes]}, fun_meta, args}}
  end

  defp find_and_replace_charlist(_), do: :error

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_graphemes_for_character_uniqueness,
      message:
        "Use `String.graphemes/1` instead of `String.to_charlist/1` when comparing with " <>
          "`String.length/1`. `to_charlist` returns codepoints while `length` counts graphemes — " <>
          "mixing them is wrong for decomposed Unicode. Under `single_codepoint_graphemes`, " <>
          "the rewrite is safe.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
