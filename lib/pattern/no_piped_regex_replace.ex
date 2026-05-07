defmodule Credence.Pattern.NoPipedRegexReplace do
  @moduledoc """
  Detects `Regex.replace` used as a pipe target and replaces it with
  `String.replace`, which accepts the string as its first argument.

  `Regex.replace/3` expects `(regex, string, replacement)` — regex first.
  When used in a pipeline, the pipe injects the left-hand value as the
  first argument, putting the string where the regex should be:

      input |> Regex.replace(~r/[^a-z0-9]/, "")
      # becomes: Regex.replace(input, ~r/[^a-z0-9]/, "")
      #                        ^^^^^ string in regex position — crash

  `String.replace/3` takes `(string, pattern, replacement)` and accepts
  regex patterns, so it is a drop-in replacement that works in pipelines:

      input |> String.replace(~r/[^a-z0-9]/, "")
  """
  @behaviour Credence.Pattern.Rule

  @impl true
  def priority, do: 50

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:|>, meta,
         [
           _left,
           {{:., _, [{:__aliases__, _, [:Regex]}, :replace]}, _, _args}
         ]} = node,
        acc ->
          {node, [build_issue(meta) | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    source
    |> String.split("\n")
    |> Enum.map(&fix_line/1)
    |> Enum.join("\n")
  end

  # Only replace Regex.replace when preceded by |> on the same line
  defp fix_line(line) do
    Regex.replace(~r/(\|>\s*)Regex\.replace\(/, line, "\\1String.replace(")
  end

  defp build_issue(meta) do
    %Credence.Issue{
      rule: :no_piped_regex_replace,
      message:
        "`Regex.replace/3` expects `(regex, string, replacement)` but the pipe " <>
          "injects the string as the first argument. Use `String.replace/3` instead, " <>
          "which takes the string first and accepts regex patterns.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
