defmodule Credence.Syntax.NoMapArrowInFunctionCallAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoMapArrowInFunctionCall

  defp analyze(code), do: NoMapArrowInFunctionCall.analyze(code)

  describe "flags a Map.put whose pair is written with an arrow" do
    test "with a variable key" do
      assert [%Issue{rule: :no_map_arrow_in_function_call, meta: %{line: 1}}] =
               analyze("Map.put(%{}, key => value)")
    end

    test "with an atom key" do
      assert [%Issue{rule: :no_map_arrow_in_function_call}] = analyze("Map.put(%{}, :key => value)")
    end

    test "with a string key" do
      assert [%Issue{rule: :no_map_arrow_in_function_call}] =
               analyze(~S'Map.put(%{}, "key" => value)')
    end

    test "with a key whose column the parser counts in graphemes" do
      # A combining accent, a ZWJ emoji and a flag are one column each; the
      # blamed column has to land on the arrow for the rule to fire at all.
      assert [%Issue{rule: :no_map_arrow_in_function_call}] =
               analyze(~S'Map.put(%{}, "éx👨‍👩‍👧🇬🇧" => value)')
    end

    test "with a parenthesised key expression" do
      assert [%Issue{rule: :no_map_arrow_in_function_call}] =
               analyze("Map.put(%{}, normalize(key) => value)")
    end

    test "inside a module, reporting the arrow's line" do
      code = """
      defmodule Repro do
        def build_map(key, value) do
          Map.put(%{}, key => value)
        end
      end
      """

      assert [%Issue{rule: :no_map_arrow_in_function_call, meta: %{line: 3}}] = analyze(code)
    end
  end

  describe "leaves valid code alone" do
    test "a map literal built with arrows" do
      assert analyze(~S'%{"key" => "val"}') == []
    end

    test "a three-argument Map.put" do
      assert analyze("Map.put(%{}, :key, value)") == []
    end

    test "an arrow in a file that fails to parse for an unrelated reason" do
      # The syntax phase runs every rule's fix over any source that will not
      # parse, so a good arrow in a broken file must stay untouched.
      code = """
      Map.merge(%{}, %{a => 1})
      foo do
      """

      assert analyze(code) == []
    end

    test "the Enum.reduce-into-a-map idiom in a file that fails to parse" do
      code = """
      acc = Enum.reduce(l, %{}, fn x, acc -> Map.put(acc, x, %{k => 1}) end)
      foo(
      """

      assert analyze(code) == []
    end

    test "an arrow that only appears inside a string" do
      code = """
      x = "Map.put(%{}, a => b)"
      foo do
      """

      assert analyze(code) == []
    end
  end

  describe "refuses the shapes it has no safe repair for" do
    test "two pairs, whose comma repair would invent Map.put/5" do
      assert analyze("Map.put(%{}, a => 1, b => 2)") == []
    end

    test "a trailing argument, whose comma repair would invent Map.put/4" do
      assert analyze("Map.put(%{}, k => v, extra)") == []
    end

    test "a call whose arity we cannot know" do
      assert analyze("foo(%{}, a => b)") == []
    end

    test "a Map.put whose first argument is not an empty map" do
      assert analyze("Map.put(acc, k => v)") == []
    end

    test "a keyword-style arrow in tuple braces (another rule's business)" do
      assert analyze(~S'{"key" => "val"}') == []
    end

    test "a call split across lines" do
      code = """
      Map.put(%{},
        key => value)
      """

      assert analyze(code) == []
    end

    test "a key expression holding a comma of its own" do
      assert analyze("Map.put(%{}, foo(a, b) => v)") == []
    end

    test "a file with a second, unaccounted-for parse error" do
      code = """
      defmodule M do
        def f, do: Map.put(%{}, a => 1)
      """

      assert analyze(code) == []
    end

    test "two offending calls — the first repair alone does not make the file parse" do
      code = """
      Map.put(%{}, a => 1)
      Map.put(%{}, b => 2)
      """

      assert analyze(code) == []
    end
  end
end
