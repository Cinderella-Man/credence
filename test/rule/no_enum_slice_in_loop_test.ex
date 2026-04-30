defmodule Credence.Rule.NoEnumSliceInLoopTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoEnumSliceInLoop.check(ast, [])
  end

  describe "NoEnumSliceInLoop" do
    test "passes code using chunk_every instead of slice" do
      code = """
      defmodule GoodNgram do
        def ngrams(list, n) do
          list
          |> Enum.chunk_every(n, 1, :discard)
          |> Enum.map(&Enum.join/1)
        end
      end
      """

      assert check(code) == []
    end

    test "detects direct Enum.slice/3 usage" do
      code = """
      defmodule BadSlice do
        def window(list, n) do
          Enum.slice(list, 0, n)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)

      assert %Issue{} = issue
      assert issue.rule == :no_enum_slice_in_loop
      assert issue.severity == :warning
      assert issue.message =~ "Enum.slice/3"
      assert issue.message =~ "O(n)"
      assert issue.meta.line != nil
    end

    test "detects Enum.slice inside for-comprehension (loop case)" do
      code = """
      defmodule BadLoop do
        def windows(list, n) do
          for i <- 0..length(list) do
            Enum.slice(list, i, n)
          end
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
    end

    test "detects Enum.slice inside Enum.map loop" do
      code = """
      defmodule BadMap do
        def windows(list, n) do
          Enum.map(0..length(list), fn i ->
            Enum.slice(list, i, n)
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
    end

    test "detects recursive slicing pattern (manual sliding window)" do
      code = """
      defmodule BadRecursion do
        def walk(i, list, n) when i < length(list) do
          Enum.slice(list, i, n)
          walk(i + 1, list, n)
        end

        def walk(_, _, _), do: :ok
      end
      """

      issues = check(code)

      assert length(issues) == 2

      assert Enum.any?(issues, fn issue ->
               issue.message =~ "recursive" or issue.meta.function == :walk
             end)
    end

    test "ignores Enum.slice outside loop contexts" do
      code = """
      defmodule MultipleBad do
        def a(list), do: Enum.slice(list, 0, 2)
        def b(list), do: Enum.slice(list, 1, 3)
      end
      """

      assert check(code) == []
    end

    test "ignores Enum.slice in isolated non-loop usage (still flagged by rule, but consistent)" do
      code = """
      defmodule EdgeCase do
        def single(list) do
          Enum.slice(list, 0, 1)
        end
      end
      """

      issues = check(code)

      # This rule is intentionally strict: even single use is flagged
      assert length(issues) == 1
    end
  end
end
