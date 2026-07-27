defmodule Credence.Syntax.NoKeywordInsideTupleBraceFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoKeywordInsideTupleBrace

  defp analyze(code), do: NoKeywordInsideTupleBrace.analyze(code)
  defp fix(code), do: NoKeywordInsideTupleBrace.fix(code)

  describe "prefixes the offending brace with %" do
    test "in a list element and as a map value" do
      code = """
      defmodule TupleKeywordTest do
        def build_step(name, compensation) do
          %{name: name, data: [{step_name: name, compensation: compensation}]}
        end

        def build_completed(name, compensation) do
          [{step_name: name, compensation: compensation}]
        end
      end
      """

      expected = """
      defmodule TupleKeywordTest do
        def build_step(name, compensation) do
          %{name: name, data: [%{step_name: name, compensation: compensation}]}
        end

        def build_completed(name, compensation) do
          [%{step_name: name, compensation: compensation}]
        end
      end
      """

      confirm_fix(fix(code), expected)
    end

    test "for every occurrence in the file" do
      code = """
      a = {x: 1}
      b = {y: 2}
      c = {z: 3}
      """

      expected = """
      a = %{x: 1}
      b = %{y: 2}
      c = %{z: 3}
      """

      confirm_fix(fix(code), expected)
    end

    test "when the braces are nested inside one another" do
      code = "x = {a: {b: 1}}"

      expected = "x = %{a: %{b: 1}}"

      confirm_fix(fix(code), expected)
    end

    test "when the pairs continue on a later line, without re-indenting" do
      code = """
      x = {a: 1,
        b: 2}
      """

      expected = """
      x = %{a: 1,
        b: 2}
      """

      confirm_fix(fix(code), expected)
    end

    test "when a value string contains the closing brace" do
      code = ~S'x = {a: "}", b: 1}'

      expected = ~S'x = %{a: "}", b: 1}'

      confirm_fix(fix(code), expected)
    end

    test "when a value is the } character literal" do
      code = "x = {a: ?}, b: 1}"

      expected = "x = %{a: ?}, b: 1}"

      confirm_fix(fix(code), expected)
    end

    test "when the keys are do: and else:" do
      code = "x = {do: 1, else: 2}"

      expected = "x = %{do: 1, else: 2}"

      confirm_fix(fix(code), expected)
    end

    test "in a typespec" do
      code = """
      defmodule M do
        @type t :: {name: String.t()}
      end
      """

      expected = """
      defmodule M do
        @type t :: %{name: String.t()}
      end
      """

      confirm_fix(fix(code), expected)
    end

    test "on a line carrying a combining accent and a ZWJ emoji before the brace" do
      # `e` + U+0301 is two codepoints but one grapheme — one parser column, like
      # the precomposed é and the three-person emoji beside it.
      code = ~S'x = "éé 👨‍👩‍👧" ; y = {a: 1}'

      expected = ~S'x = "éé 👨‍👩‍👧" ; y = %{a: 1}'

      confirm_fix(fix(code), expected)
    end
  end

  describe "the fix clears its own flag and yields parseable code" do
    test "fixed output no longer flags" do
      code = """
      defmodule TupleKeywordTest do
        def build_completed(name, compensation) do
          [{step_name: name, compensation: compensation}]
        end
      end
      """

      assert analyze(fix(code)) == []
    end

    test "fixed output is well-formed" do
      code = """
      defmodule TupleKeywordTest do
        def build_step(name, compensation) do
          %{name: name, data: [{step_name: name, compensation: compensation}]}
        end

        def build_completed(name, compensation) do
          [{step_name: name, compensation: compensation}]
        end
      end
      """

      assert valid_syntax?(fix(code))
    end
  end

  describe "leaves everything else byte-identical" do
    test "valid code with a struct pattern and a nested map" do
      code = """
      defmodule PlugTest do
        def extract_user(%Plug.Conn{assigns: %{user_id: user_id}}) do
          user_id
        end
      end
      """

      confirm_fix(fix(code), code)
    end

    test "valid code with a keyword list as a tuple's last element" do
      code = """
      defmodule GoodCode do
        def build_tuple(n) do
          {:ok, count: n, total: 2}
        end
      end
      """

      confirm_fix(fix(code), code)
    end

    test "a positional entry after the keyword list (a different parser error)" do
      code = "x = {a: 1, b}"

      confirm_fix(fix(code), code)
    end

    test "a keyword list starting on the brace's second line" do
      code = """
      x = {
        a: 1
      }
      """

      confirm_fix(fix(code), code)
    end

    test "a brace shape inside a string, with the real error elsewhere" do
      code = """
      defmodule M do
        def describe do
          "{a: 1}"
        end
      """

      confirm_fix(fix(code), code)
    end

    test "a brace shape inside a heredoc, with the real error elsewhere" do
      code = ~S'''
      defmodule M do
        @moduledoc """
        Returns {a: 1} for now.
        """
        def describe do
          :ok
        end
      '''

      confirm_fix(fix(code), code)
    end

    test "a brace shape inside a comment, with the real error elsewhere" do
      code = """
      defmodule M do
        # returns {a: 1}
        def describe do
          :ok
        end
      """

      confirm_fix(fix(code), code)
    end

    test "a closing brace beyond the search window" do
      pairs = Enum.map_join(1..30, ",\n  ", fn n -> "k#{n}: #{n}" end)

      code = """
      x = {a: 1,
        #{pairs}}
      """

      confirm_fix(fix(code), code)
    end
  end

  describe "touches only the brace the parser blames" do
    test "a shape inside a comment stays, the real one is repaired" do
      code = """
      # returns {a: 1}
      x = {b: 2}
      """

      expected = """
      # returns {a: 1}
      x = %{b: 2}
      """

      confirm_fix(fix(code), expected)
    end

    test "a shape inside a regex sigil stays, the real one is repaired" do
      code = """
      r = ~r{a: 1}
      y = {b: 2}
      """

      expected = """
      r = ~r{a: 1}
      y = %{b: 2}
      """

      confirm_fix(fix(code), expected)
    end

    test "a shape inside a string stays, the real one is repaired" do
      code = """
      s = "{a: 1}"
      y = {b: 2}
      """

      expected = """
      s = "{a: 1}"
      y = %{b: 2}
      """

      confirm_fix(fix(code), expected)
    end
  end
end
