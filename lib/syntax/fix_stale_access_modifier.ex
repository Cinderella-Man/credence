defmodule Credence.Syntax.FixStaleAccessModifier do
  @moduledoc """
  Removes non-Elixir access modifier keywords prepended to `def`/`defp`/`defmacro`/`defmacrop`.

  LLMs translating from Java, Python, or TypeScript sometimes carry over
  access modifiers as prefixes, producing code like `private defp` or
  `static def`. In Elixir, visibility is encoded in the keyword itself
  (`def` = public, `defp` = private), so the prefix is always noise.

  ## Examples

      # Garbled prefix (actual LLM output)
      pprivate defp _calculate_max_product(sorted) do
      # Fixed:
      defp _calculate_max_product(sorted) do

      # Redundant prefix
      private defp helper(x), do: x + 1
      # Fixed:
      defp helper(x), do: x + 1

      # Contradictory prefix (trusts the Elixir keyword)
      private def calculate(x), do: x * 2
      # Fixed:
      def calculate(x), do: x * 2

  The rule always trusts the Elixir keyword and discards the prefix,
  because the function body, tests, and callers are written assuming
  whatever visibility `def`/`defp` provides.
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  @prefixes ~w(pprivate private public protected static abstract final async pub export)

  @prefix_pattern @prefixes
                  |> Enum.sort_by(&(-String.length(&1)))
                  |> Enum.join("|")

  @line_regex Regex.compile!(
                "^(\\s*)(#{@prefix_pattern})\\s+(defp?|defmacrop?)\\b"
              )

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if Regex.match?(@line_regex, line), do: [build_issue(line, line_no)], else: []
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.map(&fix_line/1)
    |> Enum.join("\n")
  end

  defp fix_line(line) do
    Regex.replace(@line_regex, line, "\\1\\3", global: false)
  end

  defp build_issue(line, line_no) do
    [_, _indent, prefix, _def_keyword] = Regex.run(@line_regex, line)

    %Issue{
      rule: :stale_access_modifier,
      message:
        "`#{prefix}` is not an Elixir keyword — " <>
          "visibility is determined by `def` vs `defp`. Remove the prefix.",
      meta: %{line: line_no}
    }
  end
end
