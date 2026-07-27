defmodule Credence.Syntax.NoCatchAfterAnonFnAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoCatchAfterAnonFn

  defp analyze(code), do: NoCatchAfterAnonFn.analyze(code)

  test "flags catch after fn end" do
    code = """
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

    assert [%Issue{rule: :no_catch_after_anon_fn}] = analyze(code)
  end

  test "flags after after fn end" do
    code = """
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

    assert [%Issue{rule: :no_catch_after_anon_fn}] = analyze(code)
  end

  test "leaves good code alone" do
    # Normal code that parses fine
    assert analyze("""
    defmodule Good do
      def run do
        Enum.map([1, 2, 3], fn x -> x + 1 end)
      end
    end
    """) == []
  end

  test "leaves try/catch alone" do
    # Valid try/catch
    assert analyze("""
    defmodule GoodTry do
      def run do
        try do
          Enum.map([1, 2, 3], fn x -> x + 1 end)
        catch
          value -> value
        end
      end
    end
    """) == []
  end

  test "leaves receive/after alone" do
    # Valid receive/after
    assert analyze("""
    defmodule GoodReceive do
      def run do
        receive do
          :ok -> :ok
        after
          5000 -> :timeout
        end
      end
    end
    """) == []
  end
end
