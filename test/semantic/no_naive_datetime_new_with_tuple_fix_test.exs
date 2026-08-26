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

  test "replaces an integer microsecond with the tuple Time.new!/4 requires" do
    input = """
    defmodule NNDNWTIntegerMicrosecondRegression do
      def make_ndt(year, month, day, hour, minute) do
        NaiveDateTime.new!(Date.new!(year, month, day), {hour, minute, 0, 0})
      end
    end
    """

    expected = """
    defmodule NNDNWTIntegerMicrosecondRegression do
      def make_ndt(year, month, day, hour, minute) do
        NaiveDateTime.new!(Date.new!(year, month, day), Elixir.Time.new!(hour, minute, 0, {0, 6}))
      end
    end
    """

    emitted = fix(input, @real_message, 3)
    confirm_fix(emitted, expected)

    witness = """
    unless NNDNWTIntegerMicrosecondRegression.make_ndt(2024, 1, 2, 12, 30) ==
             ~N[2024-01-02 12:30:00.000000], do: raise("wrong datetime")
    """

    assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(emitted <> "\n" <> witness)
  end

  test "semantic pipeline dispatches the tuple repair" do
    input = """
    defmodule NNDNWTSemanticDispatchRegression do
      def go(year, month, day, hour, minute) do
        NaiveDateTime.new!(Date.new!(year, month, day), {hour, minute, 0, 0})
      end
    end
    """

    expected = """
    defmodule NNDNWTSemanticDispatchRegression do
      def go(year, month, day, hour, minute) do
        NaiveDateTime.new!(Date.new!(year, month, day), Elixir.Time.new!(hour, minute, 0, {0, 6}))
      end
    end
    """

    emitted = Credence.Semantic.fix(input)
    confirm_fix(emitted, expected)

    assert Credence.RuleHelpers.compile_and_capture(emitted) ==
             Credence.RuleHelpers.compile_and_capture(expected)
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
        NaiveDateTime.new!(date, Elixir.Time.new!(12, 30, 45, {123_456, 6}))
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
        NaiveDateTime.new!(date, Elixir.Time.new!(h, m, s))
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "uses Elixir.Time when the caller aliases another module as Time" do
    input = """
    defmodule NNDNWTAliasRegression do
      alias String, as: Time
      def go(date), do: NaiveDateTime.new!(date, {12, 30, 45})
    end
    """

    expected = """
    defmodule NNDNWTAliasRegression do
      alias String, as: Time
      def go(date), do: NaiveDateTime.new!(date, Elixir.Time.new!(12, 30, 45))
    end
    """

    emitted = fix(input, @real_message, 3)
    confirm_fix(emitted, expected)

    assert Credence.RuleHelpers.compile_and_capture(emitted) ==
             Credence.RuleHelpers.compile_and_capture(expected)
  end

  test "does not rewrite matching syntax inside quote" do
    input = """
    defmodule NNDNWTQuoteRegression do
      def ast, do: quote(do: NaiveDateTime.new!(date, {1, 2, 3}))
    end
    """

    confirm_fix(fix(input, @real_message, 2), input)
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
