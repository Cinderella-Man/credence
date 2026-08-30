defmodule Credence.Syntax.PreferCommaInTupleLiteralAnalyzeTest do
  use ExUnit.Case, async: true

  alias Credence.Issue
  alias Credence.Syntax.PreferCommaInTupleLiteral

  defp analyze(code), do: PreferCommaInTupleLiteral.analyze(code)

  describe "flags a tuple whose leading atom lost its comma" do
    test "standalone tuple" do
      code = "{:noreply state}"

      assert [%Issue{rule: :prefer_comma_in_tuple_literal, meta: %{line: 1}}] = analyze(code)
    end

    test "inside a callback body" do
      code = """
      defmodule Server do
        def handle_info(_msg, state) do
          {:noreply state}
        end
      end
      """

      assert [%Issue{rule: :prefer_comma_in_tuple_literal, meta: %{line: 3}}] = analyze(code)
    end

    test "three-element tuple missing only the first comma" do
      code = "{:reply reply, state}"

      assert [%Issue{rule: :prefer_comma_in_tuple_literal, meta: %{line: 1}}] = analyze(code)
    end

    test "tuple broken across two lines — blamed at the element's own line" do
      code = """
      {:ok
        value}
      """

      assert [%Issue{rule: :prefer_comma_in_tuple_literal, meta: %{line: 2}}] = analyze(code)
    end

    test "several in one file report once, at the first" do
      code = """
      config = {:ok state}
      other = {:error reason}
      """

      assert [%Issue{rule: :prefer_comma_in_tuple_literal, meta: %{line: 1}}] = analyze(code)
    end

    test "in a function head pattern" do
      code = "fn {:ok x} -> x end"

      assert [%Issue{rule: :prefer_comma_in_tuple_literal, meta: %{line: 1}}] = analyze(code)
    end
  end

  describe "no issue on source that parses" do
    test "the comma is already there" do
      code = "{:ok, value}"

      assert analyze(code) == []
    end

    test "an atom followed by an operator is a one-element tuple, not a missing comma" do
      code = "{:ok = x}"

      assert analyze(code) == []
    end

    test "an atom followed by a guard-style operator" do
      code = "{:ok when is_nil(x)}"

      assert analyze(code) == []
    end
  end

  describe "no issue when the brace is not a tuple's" do
    test "map literal" do
      code = "%{:ok state}"

      assert analyze(code) == []
    end

    test "struct literal" do
      code = "%Foo{:ok state}"

      assert analyze(code) == []
    end

    test "string interpolation" do
      code = ~S"""
      x = "#{:ok state}"
      """

      assert analyze(code) == []
    end
  end

  describe "no issue when the parser blames something else" do
    test "a comment mentioning the shape, next to an unrelated missing comma" do
      code = """
      # a comment mentioning {:ok result}
      values = [1, 2 3]
      """

      assert analyze(code) == []
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

      assert analyze(code) == []
    end

    test "a missing `end` around a tuple that is missing its comma" do
      code = """
      defmodule Server do
        def f do
          {:ok state}
        end
      """

      assert analyze(code) == []
    end
  end

  describe "no issue when the comma would not repair the file" do
    test "the blamed token cannot follow a comma" do
      code = "{:ok ->  x}"

      assert analyze(code) == []
    end

    test "a nested tuple leaves an error the comma does not account for" do
      code = "{{:a b} c}"

      assert analyze(code) == []
    end

    test "an uppercase atom is outside the shape" do
      code = "{:Ok state}"

      assert analyze(code) == []
    end
  end
end
