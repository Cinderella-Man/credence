defmodule Credence.Syntax.FixCaptureOperatorSyntax do
  @moduledoc """
  Fixes capture + comparison operator syntax (`&>`, `&<`, `&>=`, `&<=`).

  LLMs frequently generate `&>`, `&<`, `&>=`, `&<=` (capture + comparison
  operator) intending a function reference. Elixir's capture syntax `&` cannot
  form operators — the parser rejects `&>` with `syntax error before: '>'`.

  The fix rewrites each to its Kernel function capture (`&Kernel.>/2`, etc.).

  ## Bad (won't parse)

      :gt -> &>
      :lt -> &<

  ## Good

      :gt -> &Kernel.>/2
      :lt -> &Kernel.</2
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  # Regex matches `&>=`, `&<=`, `&>`, `&<` — longest alternatives first so
  # the engine greedily matches `&>=` before `&>` + trailing `=`.
  @capture_pattern ~r/&>=|&<=|&>|&</

  @capture_map %{
    "&>" => ">",
    "&<" => "<",
    "&>=" => ">=",
    "&<=" => "<="
  }

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      @capture_pattern
      |> Regex.scan(line)
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.map(fn match ->
        op = Map.fetch!(@capture_map, match)
        build_issue(op, line_no)
      end)
    end)
  end

  @impl true
  def fix(source) do
    Regex.replace(@capture_pattern, source, fn match ->
      op = Map.fetch!(@capture_map, match)
      "&Kernel.#{op}/2"
    end)
  end

  defp build_issue(op, line) do
    %Issue{
      rule: :fix_capture_operator_syntax,
      message:
        "Capture syntax `&#{op}` is not valid in Elixir. " <>
          "Use `&Kernel.#{op}/2` for a function reference instead.",
      meta: %{line: line}
    }
  end
end
