defmodule Credence.Syntax.FixTruncatedModuleReference do
  @moduledoc """
  Fixes truncated `__MODULE__` references caused by LLM output truncation.

  LLMs sometimes truncate `__MODULE__` to `__MODULE%` (dropping the trailing
  `_` before a `%` map literal or percent sign), producing unparseable syntax.
  This rule detects and repairs such truncations via deterministic text replacement.

  ## Bad (won't parse)

      GenServer.start_link(__MODULE%, %{key: :val}, name: __MODULE__)

  ## Good

      GenServer.start_link(__MODULE__, %{key: :val}, name: __MODULE__)
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  # Matches `__MODULE%` — the truncated form where LLM dropped trailing `_`
  # before a `%` character (typically a map literal `%{...}`).
  # Does NOT match `__MODULE__` (correct form has two trailing underscores).
  @pattern ~r/__MODULE%/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if Regex.match?(@pattern, line) do
        [build_issue(line_no)]
      else
        []
      end
    end)
  end

  @impl true
  def fix(source) do
    Regex.replace(@pattern, source, "__MODULE__")
  end

  defp build_issue(line_no) do
    %Issue{
      rule: :fix_truncated_module_reference,
      message:
        "Truncated `__MODULE__` reference (`__MODULE%`) should be `__MODULE__`.",
      meta: %{line: line_no}
    }
  end
end
