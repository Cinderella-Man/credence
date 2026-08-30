defmodule Credence.Syntax.PreferCommaInTupleLiteralFixTest do
  use ExUnit.Case, async: true

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.PreferCommaInTupleLiteral

  defp analyze(code), do: PreferCommaInTupleLiteral.analyze(code)
  defp fix(code), do: PreferCommaInTupleLiteral.fix(code)

  describe "inserts the missing comma" do
    test "standalone tuple" do
      code = "{:noreply state}"

      expected = "{:noreply, state}"

      confirm_fix(fix(code), expected)
    end

    test "inside a callback body" do
      code = """
      defmodule Server do
        def handle_info(_msg, state) do
          {:noreply state}
        end
      end
      """

      expected = """
      defmodule Server do
        def handle_info(_msg, state) do
          {:noreply, state}
        end
      end
      """

      confirm_fix(fix(code), expected)
    end

    test "three-element tuple missing only the first comma" do
      code = "{:reply reply, state}"

      expected = "{:reply, reply, state}"

      confirm_fix(fix(code), expected)
    end

    test "as a call argument" do
      code = "GenServer.reply(from, {:ok state})"

      expected = "GenServer.reply(from, {:ok, state})"

      confirm_fix(fix(code), expected)
    end

    test "in a function head pattern" do
      code = "fn {:ok x} -> x end"

      expected = "fn {:ok, x} -> x end"

      confirm_fix(fix(code), expected)
    end

    test "leading-underscore atom" do
      code = "{:_private state}"

      expected = "{:_private, state}"

      confirm_fix(fix(code), expected)
    end
  end

  describe "keeps the layout it found" do
    test "a tuple broken across two lines stays broken across two lines" do
      code = """
      {:ok
        value}
      """

      expected = """
      {:ok,
        value}
      """

      confirm_fix(fix(code), expected)
    end

    test "the blank between the elements is kept, not collapsed" do
      code = "{:ok    state}"

      expected = "{:ok,    state}"

      confirm_fix(fix(code), expected)
    end
  end

  describe "repairs every gap in the file" do
    test "two tuples, two commas" do
      code = """
      config = {:ok state}
      other = {:error reason}
      """

      expected = """
      config = {:ok, state}
      other = {:error, reason}
      """

      confirm_fix(fix(code), expected)
    end

    test "both sides of a match" do
      code = "{:ok state} = {:ok other}"

      expected = "{:ok, state} = {:ok, other}"

      confirm_fix(fix(code), expected)
    end

    test "more than one hundred missing commas" do
      code = Enum.map_join(1..101, "\n", fn n -> "value#{n} = {:ok result#{n}}" end)
      expected = String.replace(code, "{:ok result", "{:ok, result")

      confirm_fix(fix(code), expected)
    end
  end

  describe "leaves source that parses byte-identical" do
    test "the comma is already there" do
      code = "{:ok, value}"

      confirm_fix(fix(code), code)
    end

    test "an atom followed by an operator is a one-element tuple, not a missing comma" do
      code = "{:ok = x}"

      confirm_fix(fix(code), code)
    end

    test "an atom followed by a guard-style operator" do
      code = "{:ok when is_nil(x)}"

      confirm_fix(fix(code), code)
    end
  end

  describe "leaves a brace that is not a tuple's byte-identical" do
    test "map literal" do
      code = "%{:ok state}"

      confirm_fix(fix(code), code)
    end

    test "struct literal" do
      code = "%Foo{:ok state}"

      confirm_fix(fix(code), code)
    end

    test "string interpolation" do
      code = ~S"""
      x = "#{:ok state}"
      """

      confirm_fix(fix(code), code)
    end
  end

  describe "leaves a file the parser blames elsewhere byte-identical" do
    test "a comment mentioning the shape, next to an unrelated missing comma" do
      code = """
      # a comment mentioning {:ok result}
      values = [1, 2 3]
      """

      confirm_fix(fix(code), code)
    end

    test "a docstring mentioning the shape, next to an unrelated missing comma" do
      code = """
      defmodule Doc do
        @moduledoc \"\"\"
        Returns {:ok result}.
        \"\"\"

        def f, do: [1, 2 3]
      end
      """

      confirm_fix(fix(code), code)
    end

    test "a missing `end` around a tuple that is missing its comma" do
      code = """
      defmodule Server do
        def f do
          {:ok state}
        end
      """

      confirm_fix(fix(code), code)
    end
  end

  describe "leaves a gap the comma would not repair byte-identical" do
    test "the blamed token cannot follow a comma" do
      code = "{:ok ->  x}"

      confirm_fix(fix(code), code)
    end

    test "a nested tuple leaves an error the comma does not account for" do
      code = "{{:a b} c}"

      confirm_fix(fix(code), code)
    end

    test "an uppercase atom is outside the shape" do
      code = "{:Ok state}"

      confirm_fix(fix(code), code)
    end
  end

  describe "the parser's column is read in graphemes" do
    test "a combining accent before the tuple does not shift the comma" do
      code = ~S'foo("héllo", {:ok state})'

      expected = ~S'foo("héllo", {:ok, state})'

      confirm_fix(fix(code), expected)
    end

    test "a ZWJ emoji before the tuple does not shift the comma" do
      code = ~S'foo("👩‍👩‍👧‍👦", {:ok state})'

      expected = ~S'foo("👩‍👩‍👧‍👦", {:ok, state})'

      confirm_fix(fix(code), expected)
    end

    test "a flag before the tuple does not shift the comma" do
      code = ~S'foo("🇵🇱🇵🇱", {:ok state})'

      expected = ~S'foo("🇵🇱🇵🇱", {:ok, state})'

      confirm_fix(fix(code), expected)
    end
  end

  describe "the repaired file is well-formed" do
    test "the whole syntax phase discovers and applies this rule" do
      code = """
      defmodule CredencePreferCommaPipelineFixture do
        def handle_info(_msg, state), do: {:noreply state}
      end
      """

      expected = """
      defmodule CredencePreferCommaPipelineFixture do
        def handle_info(_msg, state), do: {:noreply, state}
      end
      """

      confirm_fix(Credence.Syntax.fix(code), expected)
    end

    test "fixed output no longer flags" do
      assert analyze(fix("{:noreply state}")) == []
    end

    test "fixed output parses" do
      assert valid_syntax?(fix("{:noreply state}"))
    end

    test "fixed multi-gap output parses" do
      assert valid_syntax?(
               fix("""
               config = {:ok state}
               other = {:error reason}
               """)
             )
    end
  end
end
