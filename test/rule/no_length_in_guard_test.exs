defmodule Credence.Rule.NoLengthInGuardTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoLengthInGuard.check(ast, [])
  end

  describe "NoLengthInGuard" do
    test "passes code that uses pattern matching instead of length" do
      code = """
      defmodule GoodCode do
        def process([_ | _] = list) do
          Enum.map(list, &(&1 * 2))
        end

        def process([]), do: []
      end
      """

      assert check(code) == []
    end

    test "passes code that uses length inside function body" do
      code = """
      defmodule BodyLength do
        def process(list) when is_list(list) do
          n = length(list)
          n * 2
        end
      end
      """

      assert check(code) == []
    end

    test "detects length/1 in a guard with comparison" do
      code = """
      defmodule BadGuard do
        def kth_largest(nums, k) when is_list(nums) and k <= length(nums) do
          Enum.sort(nums, :desc) |> Enum.at(k - 1)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1

      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_length_in_guard

      assert issue.message =~ "length/1"
      assert issue.message =~ "guard"
      assert issue.meta.line != nil
    end

    test "detects length/1 in a simple guard" do
      code = """
      defmodule BadSimple do
        def process(list) when length(list) > 0 do
          Enum.sum(list)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_length_in_guard
    end

    test "detects length/1 in a defp guard" do
      code = """
      defmodule BadPrivate do
        defp helper(list) when length(list) == 3 do
          :ok
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_length_in_guard
    end

    test "ignores is_list and other guards" do
      code = """
      defmodule SafeGuard do
        def process(list) when is_list(list) do
          length(list)
        end
      end
      """

      assert check(code) == []
    end
  end
end
