defmodule Credence.Syntax.NoMapArrowSyntaxInTupleBraceAnalyzeTest do
  use ExUnit.Case, async: true

  alias Credence.Issue
  alias Credence.Syntax.NoMapArrowSyntaxInTupleBrace

  defp analyze(code), do: NoMapArrowSyntaxInTupleBrace.analyze(code)

  describe "flags a tuple brace holding map arrows" do
    test "string keys inside a call" do
      code = """
      defmodule Demo do
        def body do
          Jason.encode!({"error" => "File too large", "max_bytes" => 5_242_880})
        end
      end
      """

      assert [%Issue{rule: :no_map_arrow_syntax_in_tuple_brace, meta: %{line: 3}}] = analyze(code)
    end

    test "standalone string key" do
      code = ~S'{"key" => "val"}'

      assert [%Issue{rule: :no_map_arrow_syntax_in_tuple_brace, meta: %{line: 1}}] = analyze(code)
    end

    test "atom key" do
      code = ~S'{:key => "val"}'

      assert [%Issue{rule: :no_map_arrow_syntax_in_tuple_brace, meta: %{line: 1}}] = analyze(code)
    end

    test "variable key" do
      code = "{key => val}"

      assert [%Issue{rule: :no_map_arrow_syntax_in_tuple_brace, meta: %{line: 1}}] = analyze(code)
    end

    test "integer key" do
      code = "{1 => 2}"

      assert [%Issue{rule: :no_map_arrow_syntax_in_tuple_brace, meta: %{line: 1}}] = analyze(code)
    end

    test "tuple brace nested inside a well-formed map" do
      code = ~S'%{"x" => {"a" => 1}}'

      assert [%Issue{rule: :no_map_arrow_syntax_in_tuple_brace, meta: %{line: 1}}] = analyze(code)
    end

    test "container opened on an earlier line is reported at the brace's line" do
      code = """
      Jason.encode!({
        "error" => "File too large"
      })
      """

      assert [%Issue{rule: :no_map_arrow_syntax_in_tuple_brace, meta: %{line: 1}}] = analyze(code)
    end
  end

  describe "leaves well-formed code alone" do
    test "map literal" do
      code = """
      defmodule GoodCode do
        def build_map do
          %{"error" => "File too large", "max_bytes" => 5_242_880}
        end
      end
      """

      assert analyze(code) == []
    end

    test "tuple of an atom and a string" do
      code = ~S'{:ok, "result"}'

      assert analyze(code) == []
    end

    test "tuple of numbers" do
      code = "{1, 2, 3}"

      assert analyze(code) == []
    end

    test "map with keyword-style keys" do
      code = ~S'%{key: "val"}'

      assert analyze(code) == []
    end
  end

  describe "no issue on arrow errors this rule refuses to repair" do
    # `%{"a" => 1, b}` parses but does not compile ("expected key-value pairs in
    # a map"), so turning the brace into a map would swap one broken file for
    # another. Deliberately dropped — check and fix agree on skipping it.
    test "stray non-pair element beside the arrows" do
      code = ~S'{"a" => 1, b}'

      assert analyze(code) == []
    end

    test "arrow inside a list" do
      code = "[1 => 2]"

      assert analyze(code) == []
    end

    test "arrow as a bare function argument" do
      code = "foo(a => b)"

      assert analyze(code) == []
    end

    # Owned by Credence.Syntax.NoMapArrowInFunctionCall, whose repair is a comma.
    test "arrow as a Map.put argument" do
      code = "Map.put(%{}, key => value)"

      assert analyze(code) == []
    end

    test "arrow in an anonymous function head" do
      code = "fn a => b end"

      assert analyze(code) == []
    end

    test "the nearest brace is inside the key string" do
      code = ~S'{"a{b" => 1}'

      assert analyze(code) == []
    end

    test "struct braces" do
      code = ~S'%Foo{"a" => 1}'

      assert analyze(code) == []
    end

    test "two arrow tuples in one file — one repair does not make it parse" do
      code = """
      a = {"x" => 1}
      b = {"y" => 2}
      """

      assert analyze(code) == []
    end
  end

  describe "never claims an arrow the parser did not blame" do
    test "arrow text in a string while the file fails for another reason" do
      code = """
      defmodule Demo do
        def f do
          msg = "shape is {a => 1}"
      end
      """

      assert analyze(code) == []
    end

    test "arrow text in a comment while the file fails for another reason" do
      code = """
      defmodule Demo do
        # takes {a => 1}
        def f do
      end
      """

      assert analyze(code) == []
    end
  end
end
