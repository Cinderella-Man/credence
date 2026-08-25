defmodule Credence.Syntax.PreferCondDoKeyword do
  @moduledoc """
  Repairs `cond ->` written in place of `cond do`.

  LLMs occasionally emit `cond ->` — mixing Rust/OCaml match-arm syntax into
  Elixir — where Elixir requires `cond do`. The bare `cond ->` never parses, so
  this is a REPAIR: replace the offending `cond ->` with `cond do`, opening the
  block the trailing `end` was already waiting to close. `cond do … end` is the
  only valid form, so the rewrite is behaviour-neutral.

  Detection is driven by the parser itself. The rule replaces all code-level
  `cond ->` occurrences and commits the result only when `Code.string_to_quoted/1`
  then succeeds. A `cond ->` sitting inside a string, heredoc, or comment is
  masked from replacement and is left untouched even when the file is
  unparseable for an unrelated reason.

  **That argument holds only on source that does not parse**, which is the only
  source the Syntax phase runs on. On source that already parses it is empty:
  "the result parses" is then true of every candidate, including one inside a
  literal, so the first occurrence anywhere won. Called directly on its own file
  this rule rewrote its own moduledoc — the sentence above became "Repairs
  `cond do` written in place of `cond do`". So the rule now declines a source
  that already parses, which is a no-op in the pipeline and makes the paragraph
  above true unconditionally. A repair that has nothing to repair is not a
  repair.

  ## Bad (won't parse)

      cond ->
        list == [] -> nil
        true -> Enum.min(list)
      end

  ## Good

      cond do
        list == [] -> nil
        true -> Enum.min(list)
      end
  """
  use Credence.Syntax.Rule

  alias Credence.Issue
  alias Credence.SourceMask

  # `cond` (word-boundary) then whitespace then `->` — the broken arm-syntax shape.
  @pattern ~r/\bcond\s+->/

  @impl true
  def analyze(source) do
    case repair(source) do
      {:fixed, _fixed, line} ->
        [
          %Issue{
            rule: :prefer_cond_do_keyword,
            message: "`cond ->` should be `cond do`.",
            meta: %{line: line}
          }
        ]

      :no_fix ->
        []
    end
  end

  @impl true
  def fix(source) do
    case repair(source) do
      {:fixed, fixed, _line} -> fixed
      :no_fix -> source
    end
  end

  # Replace every code-level `cond ->` and commit only when the whole source then
  # parses. SourceMask keeps literal and comment content untouched. analyze and
  # fix share this helper, so they always agree.
  #
  # The guard below is what makes that true. `parses?(candidate)` proves the
  # RESULT parses, not that the replacement repaired anything — so on a source
  # that already parsed, every candidate satisfied it and the first occurrence
  # won wherever it sat, literal or not. The Syntax phase only runs on source
  # that fails to parse, so declining here costs nothing in the pipeline and
  # closes the direct-call path this rule's own moduledoc fell through.
  defp repair(source) do
    if parses?(source), do: :no_fix, else: do_repair(source)
  end

  defp do_repair(source) do
    {lines, first_line} =
      source
      |> SourceMask.lines()
      |> Enum.with_index(1)
      |> Enum.map_reduce(nil, fn {{line, shadow}, line_no}, first_line ->
        replaced = SourceMask.replace_code(line, shadow, @pattern, "cond do")
        {replaced, first_line || if(replaced != line, do: line_no)}
      end)

    candidate = Enum.join(lines, "\n")

    if first_line && parses?(candidate),
      do: {:fixed, candidate, first_line},
      else: :no_fix
  end

  defp parses?(source), do: match?({:ok, _}, Code.string_to_quoted(source))
end
