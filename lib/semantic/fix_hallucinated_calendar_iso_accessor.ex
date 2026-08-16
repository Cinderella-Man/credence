defmodule Credence.Semantic.FixHallucinatedCalendarIsoAccessor do
  @moduledoc """
  Fixes compiler warnings about hallucinated `Calendar.ISO.date/1` and
  `Calendar.ISO.time/1` accessor calls.

  LLMs frequently hallucinate `Calendar.ISO.date(dt)` and
  `Calendar.ISO.time(dt)` as ways to decompose a DateTime into its date and
  time parts. Neither function exists (`Calendar.ISO` exports no `date` or
  `time` at any arity), producing an undefined-function compile warning:

      "Calendar.ISO.date/1 is undefined or private"

  The intended stdlib calls are `DateTime.to_date/1` and `DateTime.to_time/1`,
  whose `%Date{}`/`%Time{}` results carry exactly the fields the hallucinated
  accessor is used for (`.year`/`.month`/`.day`, `.hour`/`.minute`/`.second`),
  with the same values as the source DateTime. The fix renames just the
  flagged call — anchored at the diagnostic's line and column — leaving the
  variable binding and every other line untouched.

  Only arity-1 messages are claimed: `check` and `fix` agree, and a
  hallucinated `Calendar.ISO.date/3` has no single obvious intent. Aliased
  spellings (`alias Calendar.ISO` + `ISO.date(dt)`) are deliberately left
  unfixed — the compiler reports the expanded module path, so the anchored
  rename would not find `Calendar.ISO.` at the flagged position and no-ops
  rather than risk a wrong edit.

  `UndefinedFunction` claims this diagnostic too — it accepts every "is
  undefined or private" message — and this rule takes the slot on the default
  500 against that rule's declared 501, so the ordering is stated rather than
  inherited from where the module names sort (docs/20 §1). The catch-all
  parses only the last path segment, sees `{"ISO", "date", 1}`, has no
  replacement row for it, and its boundary check rejects the line because
  `ISO` is preceded by a `.` — it would consume the diagnostic and return the
  source unchanged, never renaming to `DateTime.to_date/1`.

  ## Bad

      defmodule Example do
        def extract_date(%DateTime{} = dt) do
          date = Calendar.ISO.date(dt)
          {date.year, date.month, date.day}
        end
      end

  ## Good

      defmodule Example do
        def extract_date(%DateTime{} = dt) do
          date = DateTime.to_date(dt)
          {date.year, date.month, date.day}
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @targets %{
    "Calendar.ISO.date/1" => {"date", "DateTime.to_date"},
    "Calendar.ISO.time/1" => {"time", "DateTime.to_time"}
  }

  @module_prefix "Calendar.ISO."

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    target(msg) != nil
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_hallucinated_calendar_iso_accessor,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg, position: {line_no, col}})
      when is_integer(line_no) and is_integer(col) do
    case target(msg) do
      nil -> source
      {func, replacement} -> rename_at(source, line_no, col, func, replacement)
    end
  end

  def fix(source, _diagnostic), do: source

  # The diagnostic column points at the function name of the flagged call.
  # The rename fires only when `Calendar.ISO.` immediately precedes that
  # column and the function name sits exactly at it — an alias, an `as:`
  # rename, or any column drift fails the anchor and returns the source
  # unchanged instead of risking an edit somewhere else on the line.
  defp rename_at(source, line_no, col, func, replacement) do
    lines = String.split(source, "\n")

    case Enum.at(lines, line_no - 1) do
      nil ->
        source

      line ->
        prefix = String.slice(line, 0, col - 1)
        rest = String.slice(line, col - 1, String.length(line))

        if String.ends_with?(prefix, @module_prefix) and String.starts_with?(rest, func) do
          kept_prefix =
            String.slice(prefix, 0, String.length(prefix) - String.length(@module_prefix))

          kept_rest = String.slice(rest, String.length(func), String.length(rest))

          lines
          |> List.replace_at(line_no - 1, kept_prefix <> replacement <> kept_rest)
          |> Enum.join("\n")
        else
          source
        end
    end
  end

  # `starts_with?` (not `contains?`) so a user module whose path merely ends
  # in `Calendar.ISO` (e.g. `MyApp.Calendar.ISO.date/1`) is never claimed.
  # The " is undefined or private" suffix keeps `/1` from matching `/12`.
  defp target(msg) do
    Enum.find_value(@targets, fn {key, rename} ->
      if String.starts_with?(msg, key <> " is undefined or private"), do: rename
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
