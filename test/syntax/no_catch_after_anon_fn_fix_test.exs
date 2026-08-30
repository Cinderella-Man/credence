defmodule Credence.Syntax.NoCatchAfterAnonFnFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoCatchAfterAnonFn
  alias Credence.RuleHelpers

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

  test "syntax pipeline discovers and applies the rule" do
    input = """
    defmodule NoCatchAfterAnonFnPipelineFixture do
      def run do
        Enum.map([1], fn x -> x end)
        catch
          value -> value
        end
      end
    end
    """

    expected = """
    defmodule NoCatchAfterAnonFnPipelineFixture do
      def run do
        try do
          Enum.map([1], fn x -> x end)
        catch
          value -> value
        end
      end
    end
    """

    {actual, applied} = Credence.Syntax.fix_with_trace(input)

    assert actual == expected
    assert {NoCatchAfterAnonFn, 1} in applied
    confirm_fix(actual, fix(input))
    assert valid_syntax?(actual)
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

  test "fixes a single-line expression" do
    input = """
    defmodule OneLine do
      def run do
        Enum.map([1], fn x -> x end)
        catch
          v -> v
        end
      end
    end
    """

    expected = """
    defmodule OneLine do
      def run do
        try do
          Enum.map([1], fn x -> x end)
        catch
          v -> v
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

  # --- no-ops: everything outside the safe core is returned byte-identical ---

  test "leaves parseable source alone" do
    code = """
    defmodule Good do
      def run do
        try do
          Enum.map([1, 2, 3], fn x -> x + 1 end)
        catch
          value -> value
        end
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves a legal receive/after alone in a file broken elsewhere" do
    code = """
    defmodule M do
      def loop(l) do
        receive do
          {:go, x} -> Enum.map(l, fn y -> y + x end)
        after
          100 -> :timeout
        end
      end

      def broken do
        1 +
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves `catch` inside a heredoc alone" do
    code = """
    defmodule M do
      def a do
        Enum.map([1], fn x -> x end)
        text = \"\"\"
    catch
    me
    \"\"\"

        text
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves an end-paren inside a trailing comment alone" do
    input = """
    defmodule CatchAfterCommentClosing do
      def run do
        dangerous_call(); # end)
        catch
          :thrown -> :caught
        end
      end

      def dangerous_call, do: throw(:thrown)
    end
    """

    emitted = fix(input)

    confirm_fix(emitted, input)
    assert analyze(input) == []
    assert RuleHelpers.compile_and_capture(emitted) == RuleHelpers.compile_and_capture(input)
  end

  test "leaves the file alone when an unrelated parse error remains" do
    code = """
    defmodule M do
      def run do
        Enum.map([1, 2, 3], fn x ->
          x + 1
        end)
        catch
          value -> value
        end
      end

      def broken do
        1 +
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves two candidate sites alone" do
    code = """
    defmodule M do
      def a do
        Enum.map([1], fn x -> x end)
        catch
          v -> v
        end
      end

      def b do
        Enum.map([1], fn x -> x end)
        catch
          v -> v
        end
      end
    end
    """

    confirm_fix(fix(code), code)
  end
end
