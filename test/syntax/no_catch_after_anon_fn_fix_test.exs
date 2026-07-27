defmodule Credence.Syntax.NoCatchAfterAnonFnFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoCatchAfterAnonFn

  defp analyze(code), do: NoCatchAfterAnonFn.analyze(code)
  defp fix(code), do: NoCatchAfterAnonFn.fix(code)

  test "fixes catch after fn end" do
    input = """
    defmodule CatchAfterAnonFn do
      def run do
        Enum.map([1, 2, 3], fn x ->
          x + 1
        end)
        catch
          value -> value
        end
      end
    end
    """

    expected = """
    defmodule CatchAfterAnonFn do
      def run do
        try do
          Enum.map([1, 2, 3], fn x ->
            x + 1
          end)
        catch
          value -> value
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes after after fn end" do
    input = """
    defmodule AfterAnonFn do
      def run do
        Enum.map([1, 2, 3], fn x ->
          x + 1
        end)
        after
          :cleanup
        end
      end
    end
    """

    expected = """
    defmodule AfterAnonFn do
      def run do
        try do
          Enum.map([1, 2, 3], fn x ->
            x + 1
          end)
        after
          :cleanup
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = """
    defmodule CatchAfterAnonFn do
      def run do
        Enum.map([1, 2, 3], fn x ->
          x + 1
        end)
        catch
          value -> value
        end
      end
    end
    """

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule CatchAfterAnonFn do
      def run do
        Enum.map([1, 2, 3], fn x ->
          x + 1
        end)
        catch
          value -> value
        end
      end
    end
    """

    assert valid_syntax?(fix(input))
  end
end
