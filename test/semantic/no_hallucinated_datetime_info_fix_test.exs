defmodule Credence.Semantic.NoHallucinatedDatetimeInfoFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedDatetimeInfo

  @real_message "DateTime.info?/1 is undefined or private"

  defp fix(source, message, line \\ 1) do
    NoHallucinatedDatetimeInfo.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces DateTime.info? with match? in do block" do
    input = """
    defmodule HallucinatedDateTimeInfo do
      @spec valid_date?(any()) :: boolean()
      def valid_date?(datetime), do: DateTime.info?(datetime)
    end
    """

    expected = """
    defmodule HallucinatedDateTimeInfo do
      @spec valid_date?(any()) :: boolean()
      def valid_date?(datetime), do: match?(%DateTime{}, datetime)
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "replaces DateTime.info? in a multi-line do block" do
    input = """
    defmodule HallucinatedDateTimeInfo do
      def valid_date?(datetime) do
        DateTime.info?(datetime)
      end
    end
    """

    expected = """
    defmodule HallucinatedDateTimeInfo do
      def valid_date?(datetime) do
        match?(%DateTime{}, datetime)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "replaces multiple DateTime.info? calls" do
    input = """
    defmodule Validator do
      def check(a, b) do
        DateTime.info?(a) and DateTime.info?(b)
      end
    end
    """

    expected = """
    defmodule Validator do
      def check(a, b) do
        match?(%DateTime{}, a) and match?(%DateTime{}, b)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule X do
      def f(x), do: DateTime.info?(x)
    end
    """

    assert valid_syntax?(fix(input, @real_message, 2))
  end

  test "returns source unchanged when no DateTime.info? present" do
    input = """
    defmodule CleanExample do
      def valid_date?(datetime), do: match?(%DateTime{}, datetime)
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "leaves an unrelated module's info?/1 call untouched" do
    input = """
    defmodule Other do
      def check(x), do: OtherMod.info?(x)
    end
    """

    confirm_fix(fix(input, @real_message, 2), input)
  end

  test "rewrites a call whose argument is itself a nested call" do
    input = """
    defmodule Nested do
      def check(a, b), do: DateTime.info?(build(a, b))
    end
    """

    expected = """
    defmodule Nested do
      def check(a, b), do: match?(%DateTime{}, build(a, b))
    end
    """

    confirm_fix(fix(input, @real_message, 2), expected)
  end
end
