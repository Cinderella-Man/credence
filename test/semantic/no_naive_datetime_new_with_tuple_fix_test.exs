defmodule Credence.Semantic.NoNaiveDatetimeNewWithTupleFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoNaiveDatetimeNewWithTuple

  @real_message "incompatible types given to NaiveDateTime.new!/2:\n\n    NaiveDateTime.new!(Date.new!(year, month, day), {hour, minute, 0, 0})\n\ngiven types:\n\n    dynamic(%Date{}), -dynamic({term(), term(), integer(), integer()})-\n\nbut expected one of:\n\n    dynamic(%Date{}), dynamic(%Time{})\n\nwhere \"day\" was given the type:\n\n    # type: dynamic()\n    # from: credence_check.ex:229:7\n    {:nth_day_of_month, day, {hour, minute}}"

  defp fix(source, message, line \\ 1) do
    NoNaiveDatetimeNewWithTuple.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces a 4-element tuple with Time.new!/4, preserving the microsecond" do
    input = """
    defmodule Example do
      def make_ndt(year, month, day, hour, minute) do
        NaiveDateTime.new!(Date.new!(year, month, day), {hour, minute, 0, 0})
      end
    end
    """

    expected = """
    defmodule Example do
      def make_ndt(year, month, day, hour, minute) do
        NaiveDateTime.new!(Date.new!(year, month, day), Time.new!(hour, minute, 0, 0))
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "preserves a non-zero microsecond value" do
    input = """
    defmodule Example do
      def go(date) do
        NaiveDateTime.new!(date, {12, 30, 45, 123_456})
      end
    end
    """

    expected = """
    defmodule Example do
      def go(date) do
        NaiveDateTime.new!(date, Time.new!(12, 30, 45, 123_456))
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "replaces a 3-element tuple with Time.new!/3" do
    input = """
    defmodule Example do
      def make_ndt(date, h, m, s) do
        NaiveDateTime.new!(date, {h, m, s})
      end
    end
    """

    expected = """
    defmodule Example do
      def make_ndt(date, h, m, s) do
        NaiveDateTime.new!(date, Time.new!(h, m, s))
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "leaves a 5-element tuple untouched (no Time.new!/5 equivalent)" do
    input = """
    defmodule Example do
      def go(date) do
        NaiveDateTime.new!(date, {12, 30, 45, 0, 0})
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), input)
  end

  test "leaves a 2-element tuple untouched" do
    input = """
    defmodule Example do
      def go(date) do
        NaiveDateTime.new!(date, {12, 30})
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), input)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def make_ndt(year, month, day, hour, minute) do
        NaiveDateTime.new!(Date.new!(year, month, day), {hour, minute, 0, 0})
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message, 3))
  end

  test "returns source unchanged when no tuple present" do
    input = """
    defmodule Example do
      def make_ndt(date, time) do
        NaiveDateTime.new!(date, time)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
