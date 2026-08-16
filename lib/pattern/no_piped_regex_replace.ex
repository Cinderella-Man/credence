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

  ## Bad

      defmodule M do
        def clean(s), do: s |> Regex.replace(~r/[^a-z]/, "")
      end

  ## Good

      defmodule M do
        def clean(s), do: s |> String.replace(~r/[^a-z]/, "")
      end
  """
  @behaviour Credence.Pattern.Rule

  @impl true
  def priority, do: 50

  @impl true
  def assumptions, do: []

  @impl true
  def unsafe_in_dsl, do: []

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:|>, meta,
         [
           _left,
           {{:., _, [{:__aliases__, _, [:Regex]}, :replace]}, _, args}
         ]} = node,
        acc ->
          if misused_pipe?(args) do
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
  def fix_patches(ast, _opts) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn
        {:|>, _meta,
         [
           _left,
           {{:., _, [{:__aliases__, _, [:Regex]} = alias_node, :replace]}, _, args}
         ]} = node,
        acc ->
          if misused_pipe?(args) do
            patch = %{range: Sourceror.get_range(alias_node), change: "String"}
            {node, [patch | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(patches)
  end

  # `regex |> Regex.replace(string, repl)` desugars to the CORRECT
  # `Regex.replace(regex, string, repl)` and must not be rewritten — doing so
  # would put a %Regex{} into `String.replace/3`'s subject slot and crash. The
  # rule only targets the misuse where the pipe injects a string into the regex
  # slot, i.e. `string |> Regex.replace(regex, repl)`. The tell is that the
  # explicit first argument (the string slot) is itself a regex; then the piped
  # value belongs in the string slot. When that arg is anything else, the piped
  # value is presumably the regex (correct usage), so we leave it alone.
  defp misused_pipe?([first | _]), do: regex_literal?(first)
  defp misused_pipe?(_), do: false

  defp regex_literal?({sigil, _, _}) when sigil in [:sigil_r, :sigil_R], do: true

  defp regex_literal?({{:., _, [{:__aliases__, _, [:Regex]}, fun]}, _, _})
       when fun in [:compile, :compile!],
       do: true

  defp regex_literal?({:|>, _, [_, right]}), do: regex_literal?(right)
  defp regex_literal?(_), do: false

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
