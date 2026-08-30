defmodule Credence.Semantic.FixHallucinatedNaiveDatetimeAccessorFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.RuleHelpers
  alias Credence.Semantic.FixHallucinatedNaiveDatetimeAccessor

  @minute_message "NaiveDateTime.minute/1 is undefined or private"
  @hour_message "NaiveDateTime.hour/1 is undefined or private"
  @day_message "NaiveDateTime.day/1 is undefined or private"
  @month_message "NaiveDateTime.month/1 is undefined or private"

  defp fix(source, message, position) do
    FixHallucinatedNaiveDatetimeAccessor.fix(source, %{
      severity: :warning,
      message: message,
      position: position
    })
  end

  defp compiles?(source), do: match?({:ok, _diagnostics}, RuleHelpers.compile_and_capture(source))

  test "rewrites NaiveDateTime.minute(dt) into dt.minute, keeping the binding" do
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

    confirm_fix(fix(input, @minute_message, {3, 28}), expected)
  end

  test "rewrites NaiveDateTime.hour(dt) into dt.hour, keeping the binding" do
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

    confirm_fix(fix(input, @hour_message, {3, 26}), expected)
  end

  test "rewrites NaiveDateTime.day(dt) into dt.day, keeping the binding" do
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

    confirm_fix(fix(input, @day_message, {3, 25}), expected)
  end

  test "rewrites NaiveDateTime.month(dt) into dt.month, keeping the binding" do
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

    confirm_fix(fix(input, @month_message, {3, 27}), expected)
  end

  test "end-to-end: the semantic phase fixes all four accessors and touches nothing else" do
    input = """
    defmodule CredenceNaiveDtCronE2E do
      def due?(dt, cron) do
        minute = NaiveDateTime.minute(dt)
        hour = NaiveDateTime.hour(dt)
        day = NaiveDateTime.day(dt)
        month = NaiveDateTime.month(dt)
        minute == cron.minute and hour == cron.hour and day == cron.day and month == cron.month
      end
    end
    """

    expected = """
    defmodule CredenceNaiveDtCronE2E do
      def due?(dt, cron) do
        minute = dt.minute
        hour = dt.hour
        day = dt.day
        month = dt.month
        minute == cron.minute and hour == cron.hour and day == cron.day and month == cron.month
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: two flagged calls on the same line are both fixed" do
    input = """
    defmodule CredenceNaiveDtSameLineE2E do
      def parts(dt) do
        {NaiveDateTime.minute(dt), NaiveDateTime.hour(dt)}
      end
    end
    """

    expected = """
    defmodule CredenceNaiveDtSameLineE2E do
      def parts(dt) do
        {dt.minute, dt.hour}
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: a string literal spelling the call on the same line survives" do
    input = """
    defmodule CredenceNaiveDtStringLiteralE2E do
      def extract(dt) do
        {"NaiveDateTime.minute(dt)", NaiveDateTime.minute(dt)}
      end
    end
    """

    expected = """
    defmodule CredenceNaiveDtStringLiteralE2E do
      def extract(dt) do
        {"NaiveDateTime.minute(dt)", dt.minute}
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: repairs aliased, piped, captured, computed, multiline, and Unicode calls" do
    input = """
    defmodule CredenceNaiveDtCallShapesE2E do
      alias NaiveDateTime, as: NDT

      def alias_call(dt), do: NDT.minute(dt)
      def prefixed(dt), do: Elixir.NaiveDateTime.minute(dt)
      def piped(dt), do: dt |> NaiveDateTime.hour()
      def captured(dts), do: Enum.map(dts, &NaiveDateTime.day/1)
      def computed, do: NaiveDateTime.month(NaiveDateTime.utc_now())
      def literal, do: NaiveDateTime.minute(~N[2026-08-25 12:34:56])
      def multiline(dt), do: NaiveDateTime.minute(
        dt
      )
      def unicode(δτ), do: NaiveDateTime.hour(δτ)
    end
    """

    expected = """
    defmodule CredenceNaiveDtCallShapesE2E do
      alias NaiveDateTime, as: NDT

      def alias_call(dt), do: dt.minute
      def prefixed(dt), do: dt.minute
      def piped(dt), do: dt.hour
      def captured(dts), do: Enum.map(dts, fn value -> value.day end)
      def computed, do: NaiveDateTime.utc_now().month
      def literal, do: ~N[2026-08-25 12:34:56].minute
      def multiline(dt), do: dt.minute
      def unicode(δτ), do: δτ.hour
    end
    """

    fixed = Credence.Semantic.fix(input)
    confirm_fix(fixed, expected)
    confirm_fix(Credence.Semantic.fix(fixed), expected)
    assert compiles?(fixed)
  end

  test "a nil argument is left unfixed (nil.minute is not a field access)" do
    input = """
    defmodule Example do
      def extract do
        x = NaiveDateTime.minute(nil)
        x
      end
    end
    """

    confirm_fix(fix(input, @minute_message, {3, 23}), input)
  end

  test "an unclaimed day_of_week diagnostic leaves the source unchanged" do
    input = """
    defmodule Example do
      def extract(dt) do
        dow = NaiveDateTime.day_of_week(dt)
        dow
      end
    end
    """

    diagnostic_message = "NaiveDateTime.day_of_week/1 is undefined or private"
    confirm_fix(fix(input, diagnostic_message, {3, 25}), input)
  end

  test "an unanchored user-module diagnostic leaves the source unchanged" do
    input = """
    defmodule Example do
      def extract(dt) do
        minute = NaiveDateTime.minute(dt)
        minute
      end
    end
    """

    diagnostic_message = "MyApp.NaiveDateTime.minute/1 is undefined or private"
    confirm_fix(fix(input, diagnostic_message, {3, 28}), input)
  end

  test "fixed flagship output compiles" do
    input = """
    defmodule CredenceNaiveDtCompiles do
      def due?(dt) do
        minute = NaiveDateTime.minute(dt)
        minute
      end
    end
    """

    assert compiles?(fix(input, @minute_message, {3, 28}))
  end

  test "compile checks contain top-level exits" do
    refute compiles?("exit(:fixture_exit)")
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def due?(dt) do
        minute = NaiveDateTime.minute(dt)
        minute
      end
    end
    """

    assert valid_syntax?(fix(input, @minute_message, {3, 28}))
  end

  test "returns source unchanged when the column does not anchor on the call" do
    input = """
    defmodule Example do
      def due?(dt) do
        minute = NaiveDateTime.minute(dt)
        minute
      end
    end
    """

    confirm_fix(fix(input, @minute_message, {3, 1}), input)
  end

  test "returns source unchanged when the flagged line does not exist" do
    input = """
    defmodule Example do
      def due?(dt), do: dt
    end
    """

    confirm_fix(fix(input, @minute_message, {99, 28}), input)
  end

  test "returns source unchanged for a line-only position (no column to anchor on)" do
    input = """
    defmodule Example do
      def due?(dt) do
        minute = NaiveDateTime.minute(dt)
        minute
      end
    end
    """

    confirm_fix(fix(input, @minute_message, 3), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @minute_message, {2, 3}), input)
  end
end
