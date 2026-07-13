defmodule Credence.Semantic.NoHallucinatedNaiveDatetimeToUnixFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedNaiveDatetimeToUnix

  @real_message "NaiveDateTime.to_unix/2 is undefined or private. Did you mean one of:\n\n      * to_unix/1\n"

  defp fix(source, message, line \\ 1) do
    NoHallucinatedNaiveDatetimeToUnix.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "strips second argument from NaiveDateTime.to_unix/2" do
    input = """
    defmodule TimeUtils do
      @epoch ~N[1970-01-01 00:00:00]

      def elapsed_seconds(started_at, now) do
        started = NaiveDateTime.to_unix(started_at, :second)
        current = NaiveDateTime.to_unix(now, :second)
        current - started
      end

      def current_unix do
        NaiveDateTime.to_unix(NaiveDateTime.utc_now(), :second)
      end
    end
    """

    expected = """
    defmodule TimeUtils do
      @epoch ~N[1970-01-01 00:00:00]

      def elapsed_seconds(started_at, now) do
        started = NaiveDateTime.to_unix(started_at)
        current = NaiveDateTime.to_unix(now)
        current - started
      end

      def current_unix do
        NaiveDateTime.to_unix(NaiveDateTime.utc_now())
      end
    end
    """

    confirm_fix(fix(input, @real_message, 5), expected)
  end

  test "fixes single-line call" do
    input = "NaiveDateTime.to_unix(dt, :second)"
    expected = "NaiveDateTime.to_unix(dt)"
    confirm_fix(fix(input, @real_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule TimeUtils do
      def elapsed_seconds(started_at, now) do
        started = NaiveDateTime.to_unix(started_at, :second)
        current = NaiveDateTime.to_unix(now, :second)
        current - started
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message, 3))
  end

  test "returns source unchanged when no NaiveDateTime.to_unix/2 call" do
    input = """
    defmodule Clean do
      def current_unix do
        NaiveDateTime.to_unix(NaiveDateTime.utc_now())
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), input)
  end

  test "returns source unchanged for to_unix/1 with other module" do
    input = """
    defmodule Clean do
      def convert(dt) do
        DateTime.to_unix(dt, :second)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), input)
  end
end
