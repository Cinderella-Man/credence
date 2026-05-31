defmodule Credence.Pattern.AvoidCharlistForIteration do
  @moduledoc """
  Readability rule: Detects `String.to_charlist/1` used in a pipe chain for
  character-by-character iteration. Converting a string to a charlist produces
  integer codepoints (e.g., `?( ` = 40) which are less readable than grapheme
  strings (e.g., `"("`).

  Use `String.graphemes/1` instead when iterating over characters via pipes.

  ## Bad

      s |> String.to_charlist() |> process_chars()

      s
      |> String.to_charlist()
      |> check_valid(0, false)

  ## Good

      s |> String.graphemes() |> process_chars()

      s
      |> String.graphemes()
      |> check_valid(0, false)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipe ending in String.to_charlist(): ... |> String.to_charlist()
        {:|>, meta, [_left, to_charlist_call]} = node, acc ->
          if to_charlist_call?(to_charlist_call) do
            {node, [build_issue(meta) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  defp to_charlist_call?(
         {{:., _, [{:__aliases__, _, [:String]}, :to_charlist]}, _, args}
       )
       when is_list(args),
       do: true

  defp to_charlist_call?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :avoid_charlist_for_iteration,
      message:
        "`String.to_charlist/1` produces integer codepoints. " <>
          "Use `String.graphemes/1` instead — grapheme strings (e.g., `\"(\"`) " <>
          "are more readable than integer codepoints (e.g., `?( `).",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
