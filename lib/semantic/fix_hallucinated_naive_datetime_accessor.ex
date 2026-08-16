defmodule Credence.Semantic.FixHallucinatedNaiveDatetimeAccessor do
  @moduledoc """
  Fixes compiler warnings about hallucinated `NaiveDateTime` accessor calls.

  LLMs frequently hallucinate `NaiveDateTime.minute/1`, `NaiveDateTime.hour/1`,
  `NaiveDateTime.day/1`, and `NaiveDateTime.month/1` — accessor functions that
  do not exist (`NaiveDateTime` exports none of these names), producing an
  undefined-function compile warning:

      "NaiveDateTime.minute/1 is undefined or private"

  Each of these is a plain field of the `%NaiveDateTime{}` struct carrying
  exactly the intended value, so the fix rewrites the flagged call into field
  access on its argument — `NaiveDateTime.minute(dt)` becomes `dt.minute` —
  anchored at the diagnostic's line and column, leaving every other byte
  untouched.

  `day_of_week` is deliberately not claimed: LLMs hallucinate
  `NaiveDateTime.day_of_week/1` too, but `%NaiveDateTime{}` has no
  `:day_of_week` field, so the same rewrite would trade the compile warning
  for a runtime `KeyError`, and the intended week convention
  (`Date.day_of_week/2` takes a `starting_on`) cannot be read off the call
  site.

  Only a call whose argument is a single plain variable is rewritten. Any
  other shape — an aliased spelling (`NDT.minute(dt)`), an `Elixir.`-prefixed
  spelling, a piped or captured form, a computed or literal argument — fails
  the anchor and no-ops rather than risk a wrong edit. (The compiler reports
  the expanded module path, so a user's own `MyApp.NaiveDateTime` is never
  claimed.)

  `UndefinedFunction` claims every "… is undefined or private", this warning
  included, and declares `priority: 501` against this rule's default 500, so
  the ordering is declared rather than alphabetical (docs/20 §1). Its repair
  is a table lookup with no `NaiveDateTime` row, and the `FunctionMatcher`
  fallback ranks only functions defined in the file under repair, so it hands
  back the source unchanged — no rename it can spell produces `dt.minute`.

  ## Bad

      defmodule ExampleFHNDA do
        def due?(dt) do
          minute = NaiveDateTime.minute(dt)
          minute
        end
      end

  ## Good

      defmodule ExampleFHNDA do
        def due?(dt) do
          minute = dt.minute
          minute
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @accessors ~w(minute hour day month)
  @module_prefix "NaiveDateTime."

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    accessor(msg) != nil
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_hallucinated_naive_datetime_accessor,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg, position: {line_no, col}})
      when is_integer(line_no) and is_integer(col) do
    case accessor(msg) do
      nil -> source
      accessor -> rewrite_at(source, line_no, col, accessor)
    end
  end

  def fix(source, _diagnostic), do: source

  # `starts_with?` (not `contains?`) so a user module whose path merely ends
  # in `NaiveDateTime` (e.g. `MyApp.NaiveDateTime.minute/1`) is never claimed.
  # The " is undefined or private" suffix keeps `/1` from matching `/12`, and
  # `day` never claims a `day_of_week/1` message (`_` breaks the `/1` match).
  defp accessor(msg) do
    Enum.find(@accessors, fn accessor ->
      String.starts_with?(msg, "#{@module_prefix}#{accessor}/1 is undefined or private")
    end)
  end

  # The diagnostic column points at the accessor name of the flagged call. The
  # rewrite fires only when `NaiveDateTime.` immediately precedes that column,
  # is not itself preceded by a `.` (`Elixir.NaiveDateTime.minute(dt)` must
  # not become `Elixir.dt.minute`), and the text at the column is exactly
  # `accessor(<variable>)`. The `nil`/`true`/`false` literals and the bare
  # underscore parse like variable names but are not fields to access, so they
  # fail the anchor too. Anything else — an alias, a piped or captured form, a
  # computed argument, column drift — returns the source unchanged instead of
  # risking a wrong edit.
  defp rewrite_at(source, line_no, col, accessor) do
    lines = String.split(source, "\n")

    with line when is_binary(line) <- Enum.at(lines, line_no - 1),
         prefix = String.slice(line, 0, col - 1),
         rest = String.slice(line, col - 1, String.length(line)),
         true <- String.ends_with?(prefix, @module_prefix),
         kept_prefix =
           String.slice(prefix, 0, String.length(prefix) - String.length(@module_prefix)),
         false <- String.ends_with?(kept_prefix, "."),
         [call, var] <- Regex.run(~r/\A#{accessor}\(([a-z_][a-zA-Z0-9_]*[?!]?)\)/, rest),
         true <- var not in ~w(_ nil true false) do
      kept_rest = String.slice(rest, String.length(call), String.length(rest))

      lines
      |> List.replace_at(line_no - 1, kept_prefix <> var <> "." <> accessor <> kept_rest)
      |> Enum.join("\n")
    else
      _ -> source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
