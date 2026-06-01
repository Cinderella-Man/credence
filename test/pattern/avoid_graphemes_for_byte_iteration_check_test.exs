defmodule Credence.Pattern.AvoidGraphemesForByteIterationCheckTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.AvoidGraphemesForByteIteration

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    AvoidGraphemesForByteIteration.check(ast, [])
  end

  describe "flags graphemes piped to Enum.all?/2 with integer predicate" do
    test "three-step pipe with inline integer comparison" do
      code =
        "string |> String.graphemes() |> Enum.all?(fn c -> c >= ?0 and c <= ?9 end)"

      assert [%Issue{rule: :avoid_graphemes_for_byte_iteration}] = check(code)
    end

    test "two-step pipe with inline integer comparison" do
      code = "String.graphemes(str) |> Enum.all?(fn c -> c >= ?0 and c <= ?9 end)"
      assert [%Issue{rule: :avoid_graphemes_for_byte_iteration}] = check(code)
    end

    test "three-step pipe with range in predicate" do
      code = "string |> String.graphemes() |> Enum.all?(fn c -> c in ?0..?9 end)"
      assert [%Issue{rule: :avoid_graphemes_for_byte_iteration}] = check(code)
    end

    test "capture with inline integer comparison" do
      code = "string |> String.graphemes() |> Enum.all?(&(&1 >= ?0 and &1 <= ?9))"
      assert [%Issue{rule: :avoid_graphemes_for_byte_iteration}] = check(code)
    end
  end

  describe "flags graphemes piped to Enum.any?/2 with integer predicate" do
    test "three-step pipe with inline integer comparison" do
      code = "string |> String.graphemes() |> Enum.any?(fn c -> c >= ?A and c <= ?Z end)"
      assert [%Issue{rule: :avoid_graphemes_for_byte_iteration}] = check(code)
    end

    test "predicate with binary pattern matching in args" do
      code = """
      string
      |> String.graphemes()
      |> Enum.any?(fn <<c>> when c >= ?A and c <= ?Z -> true; _ -> false end)
      """

      assert [%Issue{rule: :avoid_graphemes_for_byte_iteration}] = check(code)
    end
  end

  describe "flags graphemes piped to Enum.each/2 with integer predicate" do
    test "three-step pipe with inline integer comparison" do
      code =
        "string |> String.graphemes() |> Enum.each(fn c -> IO.puts(c >= ?0) end)"

      assert [%Issue{rule: :avoid_graphemes_for_byte_iteration}] = check(code)
    end
  end

  describe "flags graphemes piped to Enum.reduce with binary extraction" do
    test "reduce with <<char>> in callback args" do
      code =
        "column |> String.graphemes() |> Enum.reduce(0, fn <<char>>, acc -> acc * 26 + char end)"

      assert [%Issue{rule: :avoid_graphemes_for_byte_iteration}] = check(code)
    end

    test "reduce with multi-clause callback where one clause has binary pattern" do
      code = """
      column
      |> String.graphemes()
      |> Enum.reduce(0, fn
        <<char>>, acc when char >= ?A -> acc + char
        _, acc -> acc
      end)
      """

      assert [%Issue{rule: :avoid_graphemes_for_byte_iteration}] = check(code)
    end
  end

  describe "flags graphemes piped to Enum.map with binary extraction" do
    test "map with <<char>> in callback args" do
      code = "column |> String.graphemes() |> Enum.map(fn <<char>> -> char - ?A + 1 end)"
      assert [%Issue{rule: :avoid_graphemes_for_byte_iteration}] = check(code)
    end
  end

  describe "flags graphemes piped to Enum.flat_map with binary extraction" do
    test "flat_map with <<char>> in callback args" do
      code = "column |> String.graphemes() |> Enum.flat_map(fn <<char>> -> [char] end)"
      assert [%Issue{rule: :avoid_graphemes_for_byte_iteration}] = check(code)
    end
  end

  describe "flags graphemes piped to Enum.filter with binary extraction" do
    test "filter with <<char>> in callback args" do
      code =
        "column |> String.graphemes() |> Enum.filter(fn <<char>> when char >= ?A -> true; _ -> false end)"

      assert [%Issue{rule: :avoid_graphemes_for_byte_iteration}] = check(code)
    end
  end

  describe "flags in longer pipelines" do
    test "upstream steps before graphemes" do
      code = """
      str
      |> String.trim()
      |> String.downcase()
      |> String.graphemes()
      |> Enum.all?(fn c -> c >= ?0 and c <= ?9 end)
      """

      assert [%Issue{rule: :avoid_graphemes_for_byte_iteration}] = check(code)
    end
  end

  describe "flags multiple violations" do
    test "two violations in same module" do
      code = """
      defmodule Example do
        def a(s), do: String.graphemes(s) |> Enum.all?(fn c -> c >= ?0 end)
        def b(s), do: s |> String.graphemes() |> Enum.any?(fn c -> c in ?A..?Z end)
      end
      """

      assert length(check(code)) == 2
    end
  end

  describe "does NOT flag" do
    test "opaque capture — cannot verify predicate expects integers" do
      code = "string |> String.graphemes() |> Enum.all?(&hex_char?/1)"
      assert check(code) == []
    end

    test "opaque capture with any?" do
      code = "string |> String.graphemes() |> Enum.any?(&invalid?/1)"
      assert check(code) == []
    end

    test "opaque capture with each" do
      code = "string |> String.graphemes() |> Enum.each(&IO.puts/1)"
      assert check(code) == []
    end

    test "predicate with string comparisons (not integer)" do
      code = """
      string
      |> String.graphemes()
      |> Enum.all?(fn c -> c >= "0" and c <= "9" end)
      """

      assert check(code) == []
    end

    test "predicate using regex (needs strings)" do
      code =
        "string |> String.graphemes() |> Enum.any?(&String.match?(&1, ~r/[a-z]/))"

      assert check(code) == []
    end

    test "String.to_charlist piped to Enum.all?" do
      code = "String.to_charlist(str) |> Enum.all?(&valid?/1)"
      assert check(code) == []
    end

    test "graphemes piped to Enum.map" do
      code = "String.graphemes(str) |> Enum.map(& &1)"
      assert check(code) == []
    end

    test "graphemes piped to Enum.reduce with string callback" do
      code = """
      column
      |> String.graphemes()
      |> Enum.reduce("", fn char, acc -> acc <> char end)
      """

      assert check(code) == []
    end

    test "graphemes piped to Enum.map with string callback" do
      code = """
      column
      |> String.graphemes()
      |> Enum.map(fn char -> String.upcase(char) end)
      """

      assert check(code) == []
    end

    test "graphemes piped to Enum.count (handled by AvoidGraphemesEnumCount)" do
      code = "String.graphemes(str) |> Enum.count()"
      assert check(code) == []
    end

    test "graphemes piped to Enum.filter" do
      code = "String.graphemes(str) |> Enum.filter(&(&1 != \" \"))"
      assert check(code) == []
    end

    test "graphemes alone without pipe" do
      code = "String.graphemes(str)"
      assert check(code) == []
    end

    test "Enum.all? on non-graphemes" do
      code = "Enum.all?(list, &valid?/1)"
      assert check(code) == []
    end

    test "graphemes stored in variable then passed to Enum.all?" do
      code = """
      defmodule Example do
        def run(str) do
          g = String.graphemes(str)
          Enum.all?(g, &valid?/1)
        end
      end
      """

      assert check(code) == []
    end

    test "Enum.count/1 on graphemes is not flagged" do
      code = "str |> String.graphemes() |> Enum.count()"
      assert check(code) == []
    end

    test "longer pipeline with opaque capture" do
      code = """
      str
      |> String.trim()
      |> String.graphemes()
      |> Enum.all?(&valid?/1)
      """

      assert check(code) == []
    end
  end
end
