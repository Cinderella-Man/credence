defmodule Credence.Pattern.AvoidGraphemesEnumCount do
  @moduledoc """
  Performance rule: Detects `Enum.count/1` on the result of
  `String.graphemes/1` (without a predicate).

  Calling `String.graphemes/1` eagerly allocates a list of every grapheme
  in the string. If the goal is simply to count characters,
  `String.length/1` accomplishes this without the intermediate list.

  Note: the predicate variant (`Enum.count/2` with a filter function) is
  handled by the separate `AvoidGraphemesEnumCountWithPredicate` rule,
  which flags but does not auto-fix because the lazy-stream replacement
  can produce different results under Unicode normalization changes.

  ## Bad

      string |> String.graphemes() |> Enum.count()
      Enum.count(String.graphemes(string))

  ## Good

      String.length(string)

      # Or in a pipeline:
      string |> String.length()
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipe form: ... |> Enum.count()
        {:|>, meta, [lhs, rhs]} = node, issues ->
          if enum_count_no_pred?(rhs) and immediate_graphemes?(lhs) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        # Direct: Enum.count(String.graphemes(...))
        {{:., meta, [{:__aliases__, _, [:Enum]}, :count]}, _, [arg]} = node, issues ->
          if graphemes_call?(arg) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      # Pipe: ... |> String.graphemes() |> Enum.count()
      {:|>, _, [lhs, rhs]} = node when is_tuple(rhs) ->
        if enum_count_no_pred?(rhs) and immediate_graphemes?(lhs) do
          fix_pipe(lhs)
        else
          node
        end

      # Direct: Enum.count(String.graphemes(x))
      {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, [arg]} = node ->
        case extract_graphemes_arg(arg) do
          {:ok, subject} -> string_length_call(subject)
          :error -> node
        end

      node ->
        node
    end)
    |> Sourceror.to_string()
  end

  # String.graphemes(x) |> Enum.count() → String.length(x)
  defp fix_pipe({{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, [subject]}) do
    string_length_call(subject)
  end

  # x |> String.graphemes() |> Enum.count()
  defp fix_pipe(
         {:|>, pipe_meta, [deeper, {{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, _}]}
       ) do
    case deeper do
      {:|>, _, _} ->
        {:|>, pipe_meta, [deeper, {{:., [], [{:__aliases__, [], [:String]}, :length]}, [], []}]}

      _ ->
        string_length_call(deeper)
    end
  end

  defp fix_pipe(lhs), do: lhs

  defp string_length_call(subject) do
    {{:., [], [{:__aliases__, [], [:String]}, :length]}, [], [subject]}
  end

  defp extract_graphemes_arg({{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, [subject]}),
    do: {:ok, subject}

  defp extract_graphemes_arg(_), do: :error

  defp enum_count_no_pred?({{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, args})
       when is_list(args),
       do: length(args) == 0

  defp enum_count_no_pred?(_), do: false

  defp immediate_graphemes?({:|>, _, [_, rhs]}), do: graphemes_call?(rhs)
  defp immediate_graphemes?(other), do: graphemes_call?(other)

  defp graphemes_call?({{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, args})
       when is_list(args),
       do: true

  defp graphemes_call?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :avoid_graphemes_enum_count,
      message: """
      `String.graphemes/1 |> Enum.count()` allocates an intermediate list of \
      every grapheme in the string just to count them. `String.length/1` does \
      the same count in O(n) time without allocating the list.

      Replace the pattern with `String.length/1`:

          # Before (allocates a list):
          String.graphemes(str) |> Enum.count()
          Enum.count(String.graphemes(str))
          str |> String.graphemes() |> Enum.count()

          # After (no intermediate list):
          String.length(str)

          # In a pipeline, replace the last two steps:
          str |> String.trim() |> String.graphemes() |> Enum.count()
          # becomes:
          str |> String.trim() |> String.length()
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
