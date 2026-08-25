defmodule Credence.Semantic.FixHallucinatedCalendarIsoAccessorFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1, compiles?: 1]

  alias Credence.Semantic.FixHallucinatedCalendarIsoAccessor

  @date_message "Calendar.ISO.date/1 is undefined or private"
  @time_message "Calendar.ISO.time/1 is undefined or private"

  defp fix(source, message, position) do
    FixHallucinatedCalendarIsoAccessor.fix(source, %{
      severity: :warning,
      message: message,
      position: position
    })
  end

  test "renames Calendar.ISO.date/1 to DateTime.to_date/1, keeping the binding" do
    input = """
    defmodule Example do
      def extract_date(%DateTime{} = dt) do
        date = Calendar.ISO.date(dt)
        {date.year, date.month, date.day}
      end
    end
    """

    expected = """
    defmodule Example do
      def extract_date(%DateTime{} = dt) do
        date = DateTime.to_date(dt)
        {date.year, date.month, date.day}
      end
    end
    """

    confirm_fix(fix(input, @date_message, {3, 25}), expected)
  end

  test "renames Calendar.ISO.time/1 to DateTime.to_time/1, keeping the binding" do
    input = """
    defmodule Example do
      def extract_time(%DateTime{} = dt) do
        time = Calendar.ISO.time(dt)
        {time.hour, time.minute, time.second}
      end
    end
    """

    expected = """
    defmodule Example do
      def extract_time(%DateTime{} = dt) do
        time = DateTime.to_time(dt)
        {time.hour, time.minute, time.second}
      end
    end
    """

    confirm_fix(fix(input, @time_message, {3, 25}), expected)
  end

  test "end-to-end: the semantic phase fixes date and time calls and touches nothing else" do
    input = """
    defmodule CredenceCalendarIsoE2E do
      def extract_parts(%DateTime{} = dt) do
        date = Calendar.ISO.date(dt)
        time = Calendar.ISO.time(dt)
        {{date.year, date.month, date.day}, time.hour}
      end
    end
    """

    expected = """
    defmodule CredenceCalendarIsoE2E do
      def extract_parts(%DateTime{} = dt) do
        date = DateTime.to_date(dt)
        time = DateTime.to_time(dt)
        {{date.year, date.month, date.day}, time.hour}
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: a sibling function's same-named variable is left untouched" do
    input = """
    defmodule CredenceCalendarIsoSiblingE2E do
      def extract(dt) do
        date = Calendar.ISO.date(dt)
        {date.year, Map.get(date, :month)}
      end

      def other(date) do
        date.month
      end
    end
    """

    expected = """
    defmodule CredenceCalendarIsoSiblingE2E do
      def extract(dt) do
        date = DateTime.to_date(dt)
        {date.year, Map.get(date, :month)}
      end

      def other(date) do
        date.month
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: a valid Calendar.ISO call in the same function is left untouched" do
    input = """
    defmodule CredenceCalendarIsoValidCallE2E do
      def extract(dt, str) do
        date = Calendar.ISO.date(dt)
        parsed = Calendar.ISO.parse_date(str)
        {date.year, parsed}
      end
    end
    """

    expected = """
    defmodule CredenceCalendarIsoValidCallE2E do
      def extract(dt, str) do
        date = DateTime.to_date(dt)
        parsed = Calendar.ISO.parse_date(str)
        {date.year, parsed}
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: a string literal spelling Calendar.ISO.date on the same line survives" do
    input = """
    defmodule CredenceCalendarIsoStringLiteralE2E do
      def extract(dt) do
        {"Calendar.ISO.date", Calendar.ISO.date(dt)}
      end
    end
    """

    expected = """
    defmodule CredenceCalendarIsoStringLiteralE2E do
      def extract(dt) do
        {"Calendar.ISO.date", DateTime.to_date(dt)}
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: fixes the piped form" do
    input = """
    defmodule CredenceCalendarIsoPipedE2E do
      def extract(dt) do
        dt |> Calendar.ISO.date()
      end
    end
    """

    expected = """
    defmodule CredenceCalendarIsoPipedE2E do
      def extract(dt) do
        dt |> DateTime.to_date()
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: fixes the capture form" do
    input = """
    defmodule CredenceCalendarIsoCaptureE2E do
      def extract(dts) do
        Enum.map(dts, &Calendar.ISO.time/1)
      end
    end
    """

    expected = """
    defmodule CredenceCalendarIsoCaptureE2E do
      def extract(dts) do
        Enum.map(dts, &DateTime.to_time/1)
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: fixes an aliased Calendar.ISO call" do
    input = """
    defmodule CredenceCalendarIsoAliasE2E do
      alias Calendar.ISO

      def extract(dt) do
        date = ISO.date(dt)
        date.year
      end
    end
    """

    expected = """
    defmodule CredenceCalendarIsoAliasE2E do
      alias Calendar.ISO

      def extract(dt) do
        date = DateTime.to_date(dt)
        date.year
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "fixed flagship output compiles" do
    input = """
    defmodule CredenceCalendarIsoCompiles do
      def extract_date(%DateTime{} = dt) do
        date = Calendar.ISO.date(dt)
        {date.year, date.month, date.day}
      end
    end
    """

    assert compiles?(fix(input, @date_message, {3, 25}))
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def extract_date(%DateTime{} = dt) do
        date = Calendar.ISO.date(dt)
        {date.year, date.month, date.day}
      end
    end
    """

    assert valid_syntax?(fix(input, @date_message, {3, 25}))
  end

  test "returns source unchanged when the column does not anchor on the call" do
    input = """
    defmodule Example do
      def extract_date(%DateTime{} = dt) do
        date = Calendar.ISO.date(dt)
        {date.year, date.month, date.day}
      end
    end
    """

    confirm_fix(fix(input, @date_message, {3, 1}), input)
  end

  test "returns source unchanged when the flagged line does not exist" do
    input = """
    defmodule Example do
      def extract_date(dt), do: dt
    end
    """

    confirm_fix(fix(input, @date_message, {99, 25}), input)
  end

  test "returns source unchanged for a line-only position (no column to anchor on)" do
    input = """
    defmodule Example do
      def extract_date(%DateTime{} = dt) do
        date = Calendar.ISO.date(dt)
        {date.year, date.month, date.day}
      end
    end
    """

    confirm_fix(fix(input, @date_message, 3), input)
  end

  test "returns source unchanged when no Calendar.ISO calls present" do
    input = """
    defmodule Example do
      def extract_parts(%DateTime{} = dt) do
        {dt.year, dt.month, dt.day}
      end
    end
    """

    confirm_fix(fix(input, @date_message, {3, 25}), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @date_message, {2, 3}), input)
  end
end
