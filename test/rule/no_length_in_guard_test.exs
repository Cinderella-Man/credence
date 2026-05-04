defmodule Credence.Rule.NoLengthInGuardTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoLengthInGuard.check(ast, [])
  end

  describe "NoLengthInGuard" do
    # --- NEGATIVE CASES (should NOT flag) ---

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

    test "does not flag length(list) > 0 (handled by LengthGuardToPattern)" do
      code = """
      defmodule Fixable do
        def process(list) when length(list) > 0 do
          Enum.sum(list)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag length(list) == 3 (handled by LengthGuardToPattern)" do
      code = """
      defmodule Fixable do
        defp helper(list) when length(list) == 3 do
          :ok
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag length(list) == N for N in 1..5" do
      for n <- 1..5 do
        code = """
        defmodule Fixable#{n} do
          def check(list) when length(list) == #{n}, do: :ok
        end
        """

        assert check(code) == [], "expected no issues for length(list) == #{n}"
      end
    end

    # --- POSITIVE CASES (should flag) ---

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

    test "detects length(list) == N for N > 5" do
      code = """
      defmodule Big do
        def check(list) when length(list) == 6 do
          :ok
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_length_in_guard
    end

    test "detects length(list) > N where N is not 0" do
      code = """
      defmodule NotZero do
        def check(list) when length(list) > 2 do
          :ok
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_length_in_guard
    end

    test "flags only the unfixable part in a compound guard" do
      code = """
      defmodule Mixed do
        def process(list, k) when length(list) > 0 and k <= length(list) do
          :ok
        end
      end
      """

      issues = check(code)

      # length(list) > 0 is skipped (fixable), k <= length(list) is flagged
      assert length(issues) == 1
      assert hd(issues).rule == :no_length_in_guard
    end
  end
end
