defmodule Credence.Syntax.NoMapArrowSyntaxInTupleBraceFixTest do
  use ExUnit.Case, async: true

  import Credence.RuleCase, only: [confirm_fix: 2, compiles?: 1, valid_syntax?: 1]

  alias Credence.Syntax.NoMapArrowSyntaxInTupleBrace

  defp analyze(code), do: NoMapArrowSyntaxInTupleBrace.analyze(code)
  defp fix(code), do: NoMapArrowSyntaxInTupleBrace.fix(code)

  describe "turns the tuple brace into a map literal" do
    test "string keys inside a call" do
      code = """
      defmodule Demo do
        def body do
          Jason.encode!({"error" => "File too large", "max_bytes" => 5_242_880})
        end
      end
      """

      expected = """
      defmodule Demo do
        def body do
          Jason.encode!(%{"error" => "File too large", "max_bytes" => 5_242_880})
        end
      end
      """

      confirm_fix(fix(code), expected)
    end

    test "standalone string key" do
      code = ~S'{"key" => "val"}'

      expected = ~S'%{"key" => "val"}'

      confirm_fix(fix(code), expected)
    end

    test "atom key" do
      code = ~S'{:key => "val"}'

      expected = ~S'%{:key => "val"}'

      confirm_fix(fix(code), expected)
    end

    test "variable key" do
      code = "{key => val}"

      expected = "%{key => val}"

      confirm_fix(fix(code), expected)
    end

    test "integer key" do
      code = "{1 => 2}"

      expected = "%{1 => 2}"

      confirm_fix(fix(code), expected)
    end

    test "tuple brace nested inside a well-formed map" do
      code = ~S'%{"x" => {"a" => 1}}'

      expected = ~S'%{"x" => %{"a" => 1}}'

      confirm_fix(fix(code), expected)
    end

    test "container opened on an earlier line — only that line changes" do
      code = """
      Jason.encode!({
        "error" => "File too large"
      })
      """

      expected = """
      Jason.encode!(%{
        "error" => "File too large"
      })
      """

      confirm_fix(fix(code), expected)
    end
  end

  describe "parser columns are graphemes, so wide keys still land the %" do
    # The family emoji is one grapheme built from seven codepoints and the flag
    # is one grapheme built from two; if the rule counted codepoints or bytes it
    # would look for the arrow in the wrong place and leave the source alone.
    test "ZWJ emoji and flag keys" do
      code = ~S'{"👨‍👩‍👧‍👦" => 1, "🇵🇱" => 2}'

      expected = ~S'%{"👨‍👩‍👧‍👦" => 1, "🇵🇱" => 2}'

      confirm_fix(fix(code), expected)
    end

    # `e` plus a combining acute: two codepoints, one grapheme, one column.
    test "combining accent in the key" do
      code = ~S'{"éclair" => 1, "b" => 2}'

      expected = ~S'%{"éclair" => 1, "b" => 2}'

      confirm_fix(fix(code), expected)
    end

    # The precomposed form is one codepoint and one grapheme — same repair.
    test "precomposed accent in the key" do
      code = ~S'{"éclair" => 1, "b" => 2}'

      expected = ~S'%{"éclair" => 1, "b" => 2}'

      confirm_fix(fix(code), expected)
    end
  end

  describe "leaves the source byte-identical when it will not repair it" do
    test "map literal" do
      code = ~S'%{"error" => "File too large", "max_bytes" => 5_242_880}'

      confirm_fix(fix(code), code)
    end

    test "tuple of an atom and a string" do
      code = ~S'{:ok, "result"}'

      confirm_fix(fix(code), code)
    end

    test "stray non-pair element beside the arrows" do
      code = ~S'{"a" => 1, b}'

      confirm_fix(fix(code), code)
    end

    test "arrow inside a list" do
      code = "[1 => 2]"

      confirm_fix(fix(code), code)
    end

    test "arrow as a bare function argument" do
      code = "foo(a => b)"

      confirm_fix(fix(code), code)
    end

    test "arrow as a Map.put argument" do
      code = "Map.put(%{}, key => value)"

      confirm_fix(fix(code), code)
    end

    test "arrow in an anonymous function head" do
      code = "fn a => b end"

      confirm_fix(fix(code), code)
    end

    test "the nearest brace is inside the key string" do
      code = ~S'{"a{b" => 1}'

      confirm_fix(fix(code), code)
    end

    test "struct braces" do
      code = ~S'%Foo{"a" => 1}'

      confirm_fix(fix(code), code)
    end

    test "two arrow tuples in one file" do
      code = """
      a = {"x" => 1}
      b = {"y" => 2}
      """

      confirm_fix(fix(code), code)
    end
  end

  describe "never edits an arrow the parser did not blame" do
    test "arrow text in a string while the file fails for another reason" do
      code = """
      defmodule Demo do
        def f do
          msg = "shape is {a => 1}"
      end
      """

      confirm_fix(fix(code), code)
    end

    test "arrow text in a comment while the file fails for another reason" do
      code = """
      defmodule Demo do
        # takes {a => 1}
        def f do
      end
      """

      confirm_fix(fix(code), code)
    end
  end

  describe "the repaired source is well formed" do
    test "it parses and no longer flags" do
      code = """
      defmodule Demo do
        def body do
          Jason.encode!({"error" => "File too large", "max_bytes" => 5_242_880})
        end
      end
      """

      assert valid_syntax?(fix(code))
      assert analyze(fix(code)) == []
    end

    test "it compiles — the map holds only key/value pairs" do
      code = """
      defmodule DemoCompiles do
        def body do
          %{"error" => "File too large", "max_bytes" => 5_242_880}
        end
      end
      """

      broken = String.replace(code, "%{\"error\"", "{\"error\"")

      confirm_fix(fix(broken), code)
      assert compiles?(fix(broken))
    end
  end
end
