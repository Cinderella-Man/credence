defmodule Credence.Semantic.FixHallucinatedNaiveDatetimeAccessorFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixHallucinatedNaiveDatetimeAccessor

  @minute_msg "NaiveDateTime.minute/1 is undefined or private"
  @hour_msg "NaiveDateTime.hour/1 is undefined or private"
  @day_msg "NaiveDateTime.day/1 is undefined or private"
  @month_msg "NaiveDateTime.month/1 is undefined or private"
  @dow_msg "NaiveDateTime.day_of_week/1 is undefined or private"

  defp fix(source, message, line \\ 1) do
    FixHallucinatedNaiveDatetimeAccessor.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces NaiveDateTime.minute(dt) with dt.minute" do
    input = """
    defmodule CronMatch do
      def due?(dt) do
        minute = NaiveDateTime.minute(dt)
        minute
      end
    end
    """

    expected = """
    defmodule CronMatch do
      def due?(dt) do
        minute = dt.minute
        minute
      end
    end
    """

    confirm_fix(fix(input, @minute_msg), expected)
  end

  test "replaces NaiveDateTime.hour(dt) with dt.hour" do
    input = """
    defmodule CronMatch do
      def due?(dt) do
        hour = NaiveDateTime.hour(dt)
        hour
      end
    end
    """

    expected = """
    defmodule CronMatch do
      def due?(dt) do
        hour = dt.hour
        hour
      end
    end
    """

    confirm_fix(fix(input, @hour_msg), expected)
  end

  test "replaces NaiveDateTime.day(dt) with dt.day" do
    input = """
    defmodule CronMatch do
      def due?(dt) do
        day = NaiveDateTime.day(dt)
        day
      end
    end
    """

    expected = """
    defmodule CronMatch do
      def due?(dt) do
        day = dt.day
        day
      end
    end
    """

    confirm_fix(fix(input, @day_msg), expected)
  end

  test "replaces NaiveDateTime.month(dt) with dt.month" do
    input = """
    defmodule CronMatch do
      def due?(dt) do
        month = NaiveDateTime.month(dt)
        month
      end
    end
    """

    expected = """
    defmodule CronMatch do
      def due?(dt) do
        month = dt.month
        month
      end
    end
    """

    confirm_fix(fix(input, @month_msg), expected)
  end

  test "replaces NaiveDateTime.day_of_week(dt) inside rem() with dt.day_of_week" do
    input = """
    defmodule CronMatch do
      def due?(dt) do
        day_of_week = rem(NaiveDateTime.day_of_week(dt) + 5, 7)
        day_of_week
      end
    end
    """

    expected = """
    defmodule CronMatch do
      def due?(dt) do
        day_of_week = rem(dt.day_of_week + 5, 7)
        day_of_week
      end
    end
    """

    confirm_fix(fix(input, @dow_msg), expected)
  end

  test "fixes the full CronMatch example" do
    input = """
    defmodule CronMatch do
      def due?(dt, cron) do
        minute = NaiveDateTime.minute(dt)
        hour = NaiveDateTime.hour(dt)
        day = NaiveDateTime.day(dt)
        month = NaiveDateTime.month(dt)
        day_of_week = rem(NaiveDateTime.day_of_week(dt) + 5, 7)
        minute == cron.minute and hour == cron.hour and day == cron.day and
          month == cron.month and day_of_week == cron.day_of_week
      end
    end
    """

    expected = """
    defmodule CronMatch do
      def due?(dt, cron) do
        minute = dt.minute
        hour = dt.hour
        day = dt.day
        month = dt.month
        day_of_week = rem(dt.day_of_week + 5, 7)

        minute == cron.minute and hour == cron.hour and day == cron.day and
          month == cron.month and day_of_week == cron.day_of_week
      end
    end
    """

    confirm_fix(fix(input, @minute_msg), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule CronMatch do
      def due?(dt) do
        minute = NaiveDateTime.minute(dt)
        minute
      end
    end
    """

    assert valid_syntax?(fix(input, @minute_msg))
  end

  test "returns source unchanged when no hallucinated call present" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @minute_msg), input)
  end
end
