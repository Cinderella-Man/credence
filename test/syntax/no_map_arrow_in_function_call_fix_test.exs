defmodule Credence.Syntax.NoMapArrowInFunctionCallFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoMapArrowInFunctionCall

  defp analyze(code), do: NoMapArrowInFunctionCall.analyze(code)
  defp fix(code), do: NoMapArrowInFunctionCall.fix(code)

  describe "turns the blamed arrow into a comma" do
    test "with a variable key" do
      code = "Map.put(%{}, key => value)"

      expected = "Map.put(%{}, key, value)"

      confirm_fix(fix(code), expected)
    end

    test "with an atom key" do
      code = "Map.put(%{}, :key => value)"

      expected = "Map.put(%{}, :key, value)"

      confirm_fix(fix(code), expected)
    end

    test "with a string key" do
      code = ~S'Map.put(%{}, "key" => value)'

      expected = ~S'Map.put(%{}, "key", value)'

      confirm_fix(fix(code), expected)
    end

    test "with a key whose graphemes are wider than one codepoint" do
      code = ~S'Map.put(%{}, "éx👨‍👩‍👧🇬🇧" => value)'

      expected = ~S'Map.put(%{}, "éx👨‍👩‍👧🇬🇧", value)'

      confirm_fix(fix(code), expected)
    end

    test "with a parenthesised key expression" do
      code = "Map.put(%{}, normalize(key) => value)"

      expected = "Map.put(%{}, normalize(key), value)"

      confirm_fix(fix(code), expected)
    end

    test "inside a module, leaving every other line byte-identical" do
      code = """
      defmodule Repro do
        @moduledoc "a => b is only prose here"

        def build_map(key, value) do
          Map.put(%{}, key => value)
        end
      end
      """

      expected = """
      defmodule Repro do
        @moduledoc "a => b is only prose here"

        def build_map(key, value) do
          Map.put(%{}, key, value)
        end
      end
      """

      confirm_fix(fix(code), expected)
    end
  end

  describe "the repaired source is well-formed" do
    test "it parses" do
      assert valid_syntax?(fix("Map.put(%{}, key => value)"))
    end

    test "it no longer flags" do
      assert analyze(fix("Map.put(%{}, key => value)")) == []
    end

    test "the whole syntax phase repairs the file, not just this rule in isolation" do
      code = """
      defmodule Repro do
        def build_map(key, value) do
          Map.put(%{}, key => value)
        end
      end
      """

      expected = """
      defmodule Repro do
        def build_map(key, value) do
          Map.put(%{}, key, value)
        end
      end
      """

      confirm_fix(Credence.Syntax.fix(code), expected)
    end
  end

  describe "leaves everything it does not flag byte-identical" do
    test "a map literal built with arrows" do
      code = ~S'%{"key" => "val"}'

      confirm_fix(fix(code), code)
    end

    test "a three-argument Map.put" do
      code = "Map.put(%{}, :key, value)"

      confirm_fix(fix(code), code)
    end

    test "a good arrow in a file that fails to parse for an unrelated reason" do
      code = """
      Map.merge(%{}, %{a => 1})
      foo do
      """

      confirm_fix(fix(code), code)
    end

    test "the Enum.reduce-into-a-map idiom in a file that fails to parse" do
      code = """
      acc = Enum.reduce(l, %{}, fn x, acc -> Map.put(acc, x, %{k => 1}) end)
      foo(
      """

      confirm_fix(fix(code), code)
    end

    test "an arrow that only appears inside a string" do
      code = """
      x = "Map.put(%{}, a => b)"
      foo do
      """

      confirm_fix(fix(code), code)
    end

    test "two pairs, whose comma repair would invent Map.put/5" do
      code = "Map.put(%{}, a => 1, b => 2)"

      confirm_fix(fix(code), code)
    end

    test "a trailing argument, whose comma repair would invent Map.put/4" do
      code = "Map.put(%{}, k => v, extra)"

      confirm_fix(fix(code), code)
    end

    test "a call whose arity we cannot know" do
      code = "foo(%{}, a => b)"

      confirm_fix(fix(code), code)
    end

    test "a Map.put whose first argument is not an empty map" do
      code = "Map.put(acc, k => v)"

      confirm_fix(fix(code), code)
    end

    test "a keyword-style arrow in tuple braces" do
      code = ~S'{"key" => "val"}'

      confirm_fix(fix(code), code)
    end

    test "a call split across lines" do
      code = """
      Map.put(%{},
        key => value)
      """

      confirm_fix(fix(code), code)
    end

    test "a key expression holding a comma of its own" do
      code = "Map.put(%{}, foo(a, b) => v)"

      confirm_fix(fix(code), code)
    end

    test "a file with a second, unaccounted-for parse error" do
      code = """
      defmodule M do
        def f, do: Map.put(%{}, a => 1)
      """

      confirm_fix(fix(code), code)
    end

    test "two offending calls in one file" do
      code = """
      Map.put(%{}, a => 1)
      Map.put(%{}, b => 2)
      """

      confirm_fix(fix(code), code)
    end
  end
end
