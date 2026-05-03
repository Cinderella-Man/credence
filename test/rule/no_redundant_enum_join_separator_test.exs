defmodule Credence.Rule.NoRedundantEnumJoinSeparatorTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoRedundantEnumJoinSeparator.check(ast, [])
  end

  describe "NoRedundantEnumJoinSeparator" do
    test "passes Enum.join/1 with no separator" do
      code = """
      defmodule GoodJoin do
        def process(list) do
          list |> Enum.reverse() |> Enum.join()
        end
      end
      """

      assert check(code) == []
    end

    test "passes Enum.join with a non-empty separator" do
      code = """
      defmodule GoodSeparator do
        def to_csv(list) do
          Enum.join(list, ", ")
        end
      end
      """

      assert check(code) == []
    end

    test "passes direct Enum.join(list) call with no separator" do
      code = """
      defmodule GoodDirect do
        def combine(list) do
          Enum.join(list)
        end
      end
      """

      assert check(code) == []
    end

    test "passes Enum.map_join with no separator" do
      code = """
      defmodule GoodMapJoinDefault do
        def combine(list) do
          Enum.map_join(list, &to_string/1)
        end
      end
      """

      assert check(code) == []
    end

    test "passes Enum.map_join with a non-empty separator" do
      code = """
      defmodule GoodMapJoinSeparator do
        def combine(list) do
          list |> Enum.map_join(", ", &to_string/1)
        end
      end
      """

      assert check(code) == []
    end

    test "detects piped Enum.join with empty string" do
      code = """
      defmodule BadPiped do
        def process(list) do
          list |> Enum.reverse() |> Enum.join("")
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_redundant_enum_join_separator
      assert issue.message =~ "default to an empty string"
      assert issue.meta.line != nil
    end

    test "detects direct Enum.join(list, empty_string) call" do
      code = """
      defmodule BadDirect do
        def process(list) do
          Enum.join(list, "")
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_redundant_enum_join_separator
    end

    test "detects piped Enum.map_join with empty string" do
      code = """
      defmodule BadMapJoinPiped do
        def process(list) do
          list |> Enum.map_join("", &to_string/1)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert issue.rule == :no_redundant_enum_join_separator
      assert issue.message =~ "Enum.map_join/2"
    end

    test "detects direct Enum.map_join(list, empty_string, mapper) call" do
      code = """
      defmodule BadMapJoinDirect do
        def process(list) do
          Enum.map_join(list, "", &to_string/1)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_redundant_enum_join_separator
    end

    test "detects multiple redundant joins" do
      code = """
      defmodule MultipleBad do
        def f(a, b) do
          x = Enum.join(a, "")
          y = b |> Enum.join("")
          z = Enum.map_join(a, "", &to_string/1)
          w = b |> Enum.map_join("", &to_string/1)
          {x, y, z, w}
        end
      end
      """

      issues = check(code)

      assert length(issues) == 4
    end
  end
end
