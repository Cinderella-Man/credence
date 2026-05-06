defmodule Credence.Pattern.NoLengthGuardToPatternTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoLengthGuardToPattern.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoLengthGuardToPattern.fix(code, [])
  end

  describe "NoLengthGuardToPattern check" do
    # --- POSITIVE CASES (should flag) ---

    test "flags length(list) > 0 in a guard" do
      code = """
      defmodule Bad do
        def process(list) when length(list) > 0 do
          Enum.sum(list)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      issue = hd(issues)
      assert issue.rule == :no_length_guard_to_pattern
      assert issue.message =~ "> 0"
      assert issue.message =~ "[_ | _]"
    end

    test "flags length(list) == 3 in a guard" do
      code = """
      defmodule Bad do
        defp triplet(list) when length(list) == 3 do
          List.to_tuple(list)
        end
      end
      """

      issues = check(code)
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

        issues = check(code)
        assert length(issues) == 1, "expected issue for length(list) == #{n}"
        assert hd(issues).rule == :no_length_guard_to_pattern
      end
    end

    test "flags length check inside compound guard" do
      code = """
      defmodule Bad do
        def process(list, x) when length(list) > 0 and is_integer(x) do
          :ok
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_length_guard_to_pattern
    end

    # --- NEGATIVE CASES (should NOT flag) ---

    test "does not flag length(list) == N for N > 5" do
      code = """
      defmodule Safe do
        def check(list) when length(list) == 6, do: :ok
      end
      """

      assert check(code) == []
    end

    test "does not flag length(list) > N where N is not 0" do
      code = """
      defmodule Safe do
        def check(list) when length(list) > 2, do: :ok
      end
      """

      assert check(code) == []
    end

    test "does not flag k <= length(nums)" do
      code = """
      defmodule Safe do
        def check(nums, k) when k <= length(nums), do: :ok
      end
      """

      assert check(code) == []
    end

    test "does not flag length in function body" do
      code = """
      defmodule Safe do
        def check(list) do
          length(list) > 0
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag code without guards" do
      code = """
      defmodule Safe do
        def process([_ | _] = list), do: Enum.sum(list)
        def process([]), do: 0
      end
      """

      assert check(code) == []
    end
  end

  describe "NoLengthGuardToPattern fix" do
    test "fixes length(list) > 0 into [_ | _] = list pattern" do
      code = """
      defmodule Example do
        def process(list) when length(list) > 0 do
          Enum.sum(list)
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "[_ | _] = list"
      refute fixed =~ "when"
      refute fixed =~ "length"
    end

    test "fixes length(list) == 1 into [_] = list pattern" do
      code = """
      defmodule Example do
        def singleton(list) when length(list) == 1 do
          hd(list)
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "[_] = list"
      refute fixed =~ "when"
      refute fixed =~ "length"
    end

    test "fixes length(list) == 3 into [_, _, _] = list pattern" do
      code = """
      defmodule Example do
        defp triplet(list) when length(list) == 3 do
          List.to_tuple(list)
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "[_, _, _] = list"
      refute fixed =~ "when"
      refute fixed =~ "length"
    end

    test "fixes length(list) == 5 into [_, _, _, _, _] = list pattern" do
      code = """
      defmodule Example do
        def five(list) when length(list) == 5 do
          :ok
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "[_, _, _, _, _] = list"
      refute fixed =~ "when"
      refute fixed =~ "length"
    end

    test "preserves remaining guard in compound expression" do
      code = """
      defmodule Example do
        def process(list, x) when length(list) > 0 and is_integer(x) do
          :ok
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "[_ | _] = list"
      assert fixed =~ "when"
      assert fixed =~ "is_integer(x)"
      refute fixed =~ "length"
    end

    test "preserves remaining guard when length check is on the right of and" do
      code = """
      defmodule Example do
        def process(list, x) when is_atom(x) and length(list) > 0 do
          :ok
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "[_ | _] = list"
      assert fixed =~ "when"
      assert fixed =~ "is_atom(x)"
      refute fixed =~ "length"
    end

    test "does not modify when variable is not a direct parameter" do
      code = """
      defmodule Example do
        def process(%{items: list}) when length(list) > 0 do
          :ok
        end
      end
      """

      fixed = fix(code)
      # Cannot fix — list is nested inside a map pattern, not a top-level param
      assert fixed =~ "length"
      assert fixed =~ "when"
    end

    test "does not modify length(list) == N for N > 5" do
      code = """
      defmodule Example do
        def check(list) when length(list) == 6 do
          :ok
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "length"
      assert fixed =~ "when"
    end

    test "does not modify unfixable patterns like k <= length(nums)" do
      code = """
      defmodule Example do
        def check(nums, k) when k <= length(nums) do
          :ok
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "length"
    end

    test "fixed code has no remaining issues for > 0" do
      code = """
      defmodule Example do
        def process(list) when length(list) > 0 do
          Enum.sum(list)
        end
      end
      """

      fixed = fix(code)
      {:ok, ast} = Code.string_to_quoted(fixed)
      issues = Credence.Pattern.NoLengthGuardToPattern.check(ast, [])
      assert issues == []
    end

    test "fixed code has no remaining issues for == N" do
      code = """
      defmodule Example do
        defp triplet(list) when length(list) == 3 do
          List.to_tuple(list)
        end
      end
      """

      fixed = fix(code)
      {:ok, ast} = Code.string_to_quoted(fixed)
      issues = Credence.Pattern.NoLengthGuardToPattern.check(ast, [])
      assert issues == []
    end
  end
end
