defmodule Credence.Syntax.FixPythonSpreadInMap do
  @moduledoc """
  Replaces Python's `**var` map-spread syntax with Elixir's `Map.merge/2`.

  LLMs translating from Python carry over `**kwargs` / `**rest` unpacking as
  `%{key: val, **rest}` inside map literals. In Elixir, `**` is not a valid
  operator inside `%{}` — the parser reports `syntax error before: '**'`.
  The correct Elixir equivalent is `Map.merge(%{key: val}, rest)`.

  This is a Syntax rule because `%{key: val, **rest}` won't parse in Elixir.

  ## Detected patterns

      %{streams: %{}, **state}       — map with spread at end
      %{**opts}                       — bare spread (no explicit keys)
      %{a: 1, b: 2, **defaults}      — spread after multiple keys

  Any `%{...**identifier...}` where `**` appears inside a map literal.

  ## Not flagged

  Legitimate Elixir map usage is not affected:

      %{key: value}              — plain map literal
      %{map | key: new}          — map update
      Map.merge(base, extra)     — already-correct merge

  `**` is not a valid operator in any other Elixir context, so the pattern
  `%{...**...}` is unambiguous.

  ## Bad

      def init(state), do: {:ok, %{streams: %{}, **state}}
      def connect(opts), do: %{host: "localhost", **opts}

  ## Good

      def init(state), do: {:ok, Map.merge(%{streams: %{}}, state)}
      def connect(opts), do: Map.merge(%{host: "localhost"}, opts)
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  # Greedy match: `%\{` followed by `.*` (consuming up to the LAST `**` in the
  # line), then `**`, a variable name, optional trailing whitespace, and `}`.
  # The greedy `.*` ensures we match the outermost map when maps are nested.
  @spread_pattern ~r/%\{(.*)\*\*(\w+)\s*\}/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if spread_line?(line), do: [build_issue(line_no)], else: []
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      if spread_line?(line), do: fix_line(line), else: line
    end)
  end

  defp spread_line?(line) do
    not comment?(line) and Regex.match?(@spread_pattern, line)
  end

  defp comment?(line), do: Regex.match?(~r/^\s*#/, line)

  # Iteratively replace each `**var` inside a `%{...}` with `Map.merge(%{...}, var)`.
  # The greedy `.*` in the pattern matches up to the LAST `**` in the map, so
  # multiple spreads on the same line are processed right-to-left.
  defp fix_line(line) do
    do_fix(line, line)
  end

  defp do_fix(current, original) do
    if Regex.match?(@spread_pattern, current) do
      next =
        Regex.replace(@spread_pattern, current, fn _match, content, var ->
          content = content |> String.trim() |> String.trim_trailing(" ") |> String.trim_trailing(",")
          "Map.merge(%{#{content}}, #{var})"
        end)

      if next != current, do: do_fix(next, original), else: current
    else
      current
    end
  end

  defp build_issue(line_no) do
    %Issue{
      rule: :fix_python_spread_in_map,
      message:
        "Python's `**var` spread syntax does not exist in Elixir map literals. " <>
          "Use `Map.merge(%{...}, var)` instead.",
      meta: %{line: line_no}
    }
  end
end
