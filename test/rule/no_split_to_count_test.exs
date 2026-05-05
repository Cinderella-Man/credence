defmodule Credence.Rule.NoSplitToCountTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoSplitToCount.check(ast, [])
  end

  describe "fixable?/0" do
    test "reports as not fixable" do
      assert Credence.Rule.NoSplitToCount.fixable?() == false
    end
  end

  describe "check/2 — positive cases" do
    test "flags length(String.split(str, sep)) - 1" do
      code = """
      defmodule Example do
        def count(str, target) do
          length(String.split(str, target)) - 1
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_split_to_count
      assert issue.message =~ "allocates a list"
      assert issue.message =~ "Enum.count"
    end

    test "flags pattern inside assignment" do
      code = """
      defmodule Example do
        def count(str, target) do
          count = length(String.split(str, target)) - 1
          count
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_split_to_count
    end

    test "flags pattern with string literal separator" do
      code = """
      defmodule Example do
        def count_spaces(str), do: length(String.split(str, " ")) - 1
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_split_to_count
    end

    test "flags pattern inside if/case" do
      code = """
      defmodule Example do
        def run(str, target) do
          if length(String.split(str, target)) - 1 > 3 do
            :many
          else
            :few
          end
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_split_to_count
    end

    test "flags multiple occurrences" do
      code = """
      defmodule Example do
        def run(str) do
          a = length(String.split(str, "a")) - 1
          b = length(String.split(str, "b")) - 1
          {a, b}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end
  end

  describe "check/2 — negative cases" do
    test "does not flag String.split without length" do
      code = """
      defmodule Example do
        def run(str), do: String.split(str, ",")
      end
      """

      assert check(code) == []
    end

    test "does not flag length(list) - 1 on non-split list" do
      code = """
      defmodule Example do
        def run(list), do: length(list) - 1
      end
      """

      assert check(code) == []
    end

    test "does not flag String.split piped to Enum.count" do
      code = """
      defmodule Example do
        def run(str, target) do
          str |> String.graphemes() |> Enum.count(&(&1 == target))
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag length(String.split(str, sep)) without - 1" do
      code = """
      defmodule Example do
        def run(str), do: length(String.split(str, ","))
      end
      """

      assert check(code) == []
    end

    test "does not flag length(String.split(str, sep)) - 2" do
      code = """
      defmodule Example do
        def run(str), do: length(String.split(str, ",")) - 2
      end
      """

      assert check(code) == []
    end

    test "does not flag :binary.matches approach" do
      code = """
      defmodule Example do
        def run(str, target), do: :binary.matches(str, target) |> length()
      end
      """

      assert check(code) == []
    end
  end
end
