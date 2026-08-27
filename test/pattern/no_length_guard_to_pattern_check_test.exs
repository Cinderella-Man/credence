defmodule Credence.Pattern.NoLengthGuardToPatternCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoLengthGuardToPattern

  describe "NoLengthGuardToPattern check" do
    # --- POSITIVE CASES (should flag) ---

    test "does not flag length(list) > 0 because the pattern accepts improper lists" do
      code = """
      defmodule Bad do
        def process(list) when length(list) > 0 do
          Enum.sum(list)
        end
      end
      """

      assert check(NoLengthGuardToPattern, code) == []
    end

    test "flags length(list) == 3 in a guard" do
      code = """
      defmodule Bad do
        defp triplet(list) when length(list) == 3 do
          List.to_tuple(list)
        end
      end
      """

      issues = check(NoLengthGuardToPattern, code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_length_guard_to_pattern
      assert hd(issues).message =~ "== 3"
    end

    test "flags length(list) == N for each N in 1..5" do
      for n <- 1..5 do
        code = """
        defmodule Bad#{n} do
          def check(list) when length(list) == #{n}, do: :ok
        end
        """

        issues = check(NoLengthGuardToPattern, code)
        assert length(issues) == 1, "expected issue for length(list) == #{n}"
        assert hd(issues).rule == :no_length_guard_to_pattern
      end
    end

    test "does not flag an unsafe length > 0 check inside a compound guard" do
      code = """
      defmodule Bad do
        def process(list, x) when length(list) > 0 and is_integer(x) do
          :ok
        end
      end
      """

      assert check(NoLengthGuardToPattern, code) == []
    end

    # --- NEGATIVE CASES (should NOT flag) ---

    test "does not flag length(list) == N for N > 5" do
      code = """
      defmodule Safe do
        def check(list) when length(list) == 6, do: :ok
      end
      """

      assert check(NoLengthGuardToPattern, code) == []
    end

    test "does not flag length(list) > N where N is not 0" do
      code = """
      defmodule Safe do
        def check(list) when length(list) > 2, do: :ok
      end
      """

      assert check(NoLengthGuardToPattern, code) == []
    end

    test "does not flag k <= length(nums)" do
      code = """
      defmodule Safe do
        def check(nums, k) when k <= length(nums), do: :ok
      end
      """

      assert check(NoLengthGuardToPattern, code) == []
    end

    test "does not flag length in function body" do
      code = """
      defmodule Safe do
        def check(list) do
          length(list) > 0
        end
      end
      """

      assert check(NoLengthGuardToPattern, code) == []
    end

    test "does not flag code without guards" do
      code = """
      defmodule Safe do
        def process([_ | _] = list), do: Enum.sum(list)
        def process([]), do: 0
      end
      """

      assert check(NoLengthGuardToPattern, code) == []
    end
  end
end
