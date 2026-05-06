defmodule Credence.Pattern.NoSortThenReverseUnfixableTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoSortThenReverseUnfixable.check(ast, [])
  end

  describe "check" do
    test "detects variable-mediated sort then direct reverse" do
      code = """
      defmodule BadVariable do
        def process(nums) do
          sorted = Enum.sort(nums)
          Enum.reverse(sorted)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_sort_then_reverse
      assert hd(issues).message =~ "Enum.sort(list, :desc)"
    end

    test "detects variable-mediated with pipe reverse" do
      code = """
      defmodule BadVariablePipe do
        def process(nums) do
          sorted = Enum.sort(nums)
          sorted |> Enum.reverse()
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_sort_then_reverse
    end

    test "detects variable-mediated with pipe sort" do
      code = """
      defmodule BadPipeSort do
        def process(nums) do
          sorted = nums |> Enum.sort()
          Enum.reverse(sorted)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "detects variable-mediated where variable is used elsewhere" do
      code = """
      defmodule BadSharedVar do
        def process(nums) do
          sorted = Enum.sort(nums)
          first = hd(sorted)
          desc = Enum.reverse(sorted)
          last = hd(desc)
          {first, last}
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "detects sort with explicit :asc then variable reverse" do
      code = """
      defmodule BadExplicit do
        def process(nums) do
          sorted = Enum.sort(nums, :asc)
          Enum.reverse(sorted)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "does not flag Enum.reverse on non-sorted variable" do
      code = """
      defmodule SafeReverse do
        def process(list) do
          Enum.reverse(list)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag sorted variable without reverse" do
      code = """
      defmodule SafeSort do
        def process(nums) do
          sorted = Enum.sort(nums)
          Enum.take(sorted, 3)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when different variable is reversed" do
      code = """
      defmodule SafeDifferent do
        def process(nums, other) do
          sorted = Enum.sort(nums)
          Enum.reverse(other)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.sort with :desc" do
      code = """
      defmodule GoodSort do
        def top_three(nums) do
          Enum.sort(nums, :desc) |> Enum.take(3)
        end
      end
      """

      assert check(code) == []
    end
  end
end
