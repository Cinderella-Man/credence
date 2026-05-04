defmodule Credence.Rule.NoRedundantEnumJoinSeparatorTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoRedundantEnumJoinSeparator.check(ast, [])
  end

  defp fix(code) do
    Credence.Rule.NoRedundantEnumJoinSeparator.fix(code, [])
  end

  describe "NoRedundantEnumJoinSeparator" do
    # --- POSITIVE CASES (check should flag) ---

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

    # --- NEGATIVE CASES (check should NOT flag) ---

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

    # --- FIX TESTS ---

    test "fixes direct Enum.join(list, \"\") to Enum.join(list)" do
      input = """
      defmodule FixDirect do
        def process(list) do
          Enum.join(list, "")
        end
      end
      """

      result = fix(input)

      assert result =~ "Enum.join(list)"
      refute result =~ "Enum.join(list, \"\")"
    end

    test "fixes piped Enum.join(\"\") to Enum.join()" do
      input = """
      defmodule FixPiped do
        def process(list) do
          list |> Enum.join("")
        end
      end
      """

      result = fix(input)

      assert result =~ "Enum.join()"
      refute result =~ "Enum.join(\"\")"
    end

    test "fixes piped Enum.join(\"\") in longer pipeline" do
      input = """
      defmodule FixPipeline do
        def process(list) do
          list |> Enum.reverse() |> Enum.join("")
        end
      end
      """

      result = fix(input)

      assert result =~ "Enum.join()"
      assert result =~ "Enum.reverse()"
      refute result =~ "Enum.join(\"\")"
    end

    test "fixes direct Enum.map_join(list, \"\", mapper) to Enum.map_join(list, mapper)" do
      input = """
      defmodule FixMapJoinDirect do
        def process(list) do
          Enum.map_join(list, "", &to_string/1)
        end
      end
      """

      result = fix(input)

      assert result =~ "Enum.map_join(list, &to_string/1)"
      refute result =~ "Enum.map_join(list, \"\", &to_string/1)"
    end

    test "fixes piped Enum.map_join(\"\", mapper) to Enum.map_join(mapper)" do
      input = """
      defmodule FixMapJoinPiped do
        def process(list) do
          list |> Enum.map_join("", &to_string/1)
        end
      end
      """

      result = fix(input)

      assert result =~ "Enum.map_join(&to_string/1)"
      refute result =~ "Enum.map_join(\"\", &to_string/1)"
    end

    test "fixes all four patterns in the same module" do
      input = """
      defmodule FixAll do
        def f(a, b) do
          x = Enum.join(a, "")
          y = b |> Enum.join("")
          z = Enum.map_join(a, "", &to_string/1)
          w = b |> Enum.map_join("", &to_string/1)
          {x, y, z, w}
        end
      end
      """

      result = fix(input)

      assert result =~ "Enum.join(a)"
      assert result =~ "Enum.join()"
      assert result =~ "Enum.map_join(a, &to_string/1)"
      assert result =~ "Enum.map_join(&to_string/1)"
      refute result =~ "Enum.join(a, \"\")"
      refute result =~ "Enum.join(\"\")"
      refute result =~ "Enum.map_join(a, \"\", &to_string/1)"
      refute result =~ "Enum.map_join(\"\", &to_string/1)"
    end

    test "fix preserves non-empty separator" do
      input = """
      defmodule FixPreserve do
        def process(list) do
          Enum.join(list, ", ")
        end
      end
      """

      result = fix(input)

      assert result =~ "Enum.join(list, \", \")"
    end

    test "fix preserves surrounding code structure" do
      input = """
      defmodule FixPreserve do
        @moduledoc "Test module"

        def process(list) do
          Enum.join(list, "")
        end

        def other(x), do: x + 1
      end
      """

      result = fix(input)

      assert result =~ "@moduledoc"
      assert result =~ "def other(x)"
      assert result =~ "Enum.join(list)"
      refute result =~ "Enum.join(list, \"\")"
    end

    test "fix is idempotent" do
      input = """
      defmodule Idempotent do
        def f(a, b) do
          x = Enum.join(a, "")
          y = b |> Enum.join("")
          z = Enum.map_join(a, "", &to_string/1)
          w = b |> Enum.map_join("", &to_string/1)
          {x, y, z, w}
        end
      end
      """

      first_pass = fix(input)
      second_pass = fix(first_pass)

      assert first_pass == second_pass
    end

    test "fix handles inline anonymous function mapper" do
      input = """
      defmodule FixInlineMapper do
        def process(list) do
          Enum.map_join(list, "", fn x -> String.upcase(x) end)
        end
      end
      """

      result = fix(input)

      assert result =~ "Enum.map_join(list, fn"
      refute result =~ "Enum.map_join(list, \"\", fn"
    end
  end
end
