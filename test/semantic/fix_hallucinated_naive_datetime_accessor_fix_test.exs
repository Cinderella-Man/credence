defmodule Credence.Semantic.FixHallucinatedNaiveDatetimeAccessorFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1, compiles?: 1]

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

  test "end-to-end: an aliased call is deliberately left unfixed (anchor requires NaiveDateTime.)" do
    input = """
    defmodule CredenceNaiveDtAliasAsE2E do
      alias NaiveDateTime, as: NDT

      def extract(dt) do
        minute = NDT.minute(dt)
        minute
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), input)
  end

  test "end-to-end: an Elixir.-prefixed call is deliberately left unfixed" do
    input = """
    defmodule CredenceNaiveDtElixirPrefixE2E do
      def extract(dt) do
        minute = Elixir.NaiveDateTime.minute(dt)
        minute
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), input)
  end

  test "end-to-end: the piped form is deliberately left unfixed (no variable argument)" do
    input = """
    defmodule CredenceNaiveDtPipedE2E do
      def extract(dt) do
        dt |> NaiveDateTime.minute()
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), input)
  end

  test "end-to-end: the capture form is deliberately left unfixed" do
    input = """
    defmodule CredenceNaiveDtCaptureE2E do
      def extract(dts) do
        Enum.map(dts, &NaiveDateTime.minute/1)
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), input)
  end

  test "end-to-end: a computed argument is deliberately left unfixed" do
    input = """
    defmodule CredenceNaiveDtComputedArgE2E do
      def extract do
        NaiveDateTime.minute(NaiveDateTime.utc_now())
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), input)
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
