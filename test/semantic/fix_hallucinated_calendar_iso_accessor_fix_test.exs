defmodule Credence.Semantic.FixHallucinatedCalendarIsoAccessorFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixHallucinatedCalendarIsoAccessor

  @date_message "Calendar.ISO.date/1 is undefined or private"
  @time_message "Calendar.ISO.time/1 is undefined or private"

  defp fix(source, message, line \\ 1) do
    FixHallucinatedCalendarIsoAccessor.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces Calendar.ISO.date/1 with direct field access" do
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
        {dt.year, dt.month, dt.day}
      end
    end
    """

    confirm_fix(fix(input, @date_message), expected)
  end

  test "replaces Calendar.ISO.time/1 with direct field access" do
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
        {dt.hour, dt.minute, dt.second}
      end
    end
    """

    confirm_fix(fix(input, @time_message), expected)
  end

  test "fixes both date and time calls in one pass" do
    input = """
    defmodule Example do
      def extract_parts(%DateTime{} = dt) do
        date = Calendar.ISO.date(dt)
        time = Calendar.ISO.time(dt)
        {{date.year, date.month, date.day}, time.hour}
      end
    end
    """

    expected = """
    defmodule Example do
      def extract_parts(%DateTime{} = dt) do
        {{dt.year, dt.month, dt.day}, dt.hour}
      end
    end
    """

    confirm_fix(fix(input, @date_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def extract_parts(%DateTime{} = dt) do
        date = Calendar.ISO.date(dt)
        time = Calendar.ISO.time(dt)
        {{date.year, date.month, date.day}, time.hour}
      end
    end
    """

    assert valid_syntax?(fix(input, @date_message))
  end

  test "returns source unchanged when no Calendar.ISO calls present" do
    input = """
    defmodule Example do
      def extract_parts(%DateTime{} = dt) do
        {dt.year, dt.month, dt.day}
      end
    end
    """

    confirm_fix(fix(input, @date_message), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @date_message), input)
  end
end
