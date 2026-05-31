defmodule Credence.Pattern.AvoidGraphemesForByteIterationCheckTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.AvoidGraphemesForByteIteration

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    AvoidGraphemesForByteIteration.check(ast, [])
  end

  describe "flags graphemes piped to Enum.all?/2" do
    test "three-step pipe with capture" do
      code = "string |> String.graphemes() |> Enum.all?(&hex_char?/1)"
      assert [%Issue{rule: :avoid_graphemes_for_byte_iteration}] = check(code)
    end

    test "two-step pipe with capture" do
      code = "String.graphemes(str) |> Enum.all?(&hex_char?/1)"
      assert [%Issue{rule: :avoid_graphemes_for_byte_iteration}] = check(code)
    end

    test "three-step pipe with anonymous function" do
      code = """
      string
      |> String.graphemes()
      |> Enum.all?(fn c -> c >= "0" and c <= "9" end)
      """

      assert [%Issue{rule: :avoid_graphemes_for_byte_iteration}] = check(code)
    end
  end

  describe "flags graphemes piped to Enum.any?/2" do
    test "three-step pipe" do
      code = "string |> String.graphemes() |> Enum.any?(&invalid?/1)"
      assert [%Issue{rule: :avoid_graphemes_for_byte_iteration}] = check(code)
    end
  end

  describe "flags graphemes piped to Enum.each/2" do
    test "three-step pipe" do
      code = "string |> String.graphemes() |> Enum.each(&IO.puts/1)"
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
      |> Enum.all?(&valid?/1)
      """

      assert [%Issue{rule: :avoid_graphemes_for_byte_iteration}] = check(code)
    end
  end

  describe "flags multiple violations" do
    test "two violations in same module" do
      code = """
      defmodule Example do
        def a(s), do: String.graphemes(s) |> Enum.all?(&valid?/1)
        def b(s), do: s |> String.graphemes() |> Enum.any?(&invalid?/1)
      end
      """

      assert length(check(code)) == 2
    end
  end

  describe "does NOT flag" do
    test "String.to_charlist piped to Enum.all?" do
      code = "String.to_charlist(str) |> Enum.all?(&valid?/1)"
      assert check(code) == []
    end

    test "graphemes piped to Enum.map" do
      code = "String.graphemes(str) |> Enum.map(& &1)"
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
  end
end
