defmodule Credence.Syntax.PreferScanOverScanl do
  @moduledoc """
  Detects `Enum.scanl/3` (a hallucinated function from Haskell/Python) and
  rewrites it to `Enum.scan/3`.

  LLMs translating from Haskell or Python generate `Enum.scanl/3` for
  computing running/prefix accumulations. In Elixir, `Enum.scanl/3` does
  not exist — the correct equivalent is `Enum.scan/3`, which has identical
  behaviour: it applies a function to each element and an accumulator,
  producing a list of intermediate accumulator values.

  The rule is narrowed to the `/3` arity form to avoid ambiguity with
  `Enum.scan/2` (which takes a default accumulator from the first element).

  ## Detected patterns

      Enum.scanl(list, acc, fun)

  ## Not flagged

      Enum.scan(list, acc, fun)     — already correct
      Enum.scan(list, fun)          — /2 form, different function
      Enum.scanning(list, acc, fun) — different function name

  ## Bad

      Enum.scanl([1, 2, 3], 0, &+/2)

  ## Good

      Enum.scan([1, 2, 3], 0, &+/2)
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  @scanl_prefix "Enum.scanl("

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if String.contains?(line, @scanl_prefix) do
        [build_issue(line_no)]
      else
        []
      end
    end)
  end

  @impl true
  def fix(source) do
    String.replace(source, @scanl_prefix, "Enum.scan(")
  end

  defp build_issue(line_no) do
    %Issue{
      rule: :prefer_scan_over_scanl,
      message:
        "`Enum.scanl/3` does not exist in Elixir. " <>
          "Use `Enum.scan/3` instead — it has identical behaviour.",
      meta: %{line: line_no}
    }
  end
end
