defmodule Credence.Pattern.NoLengthGuardToPatternFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoLengthGuardToPattern

  describe "NoLengthGuardToPattern fix" do
    test "leaves length(list) > 0 unchanged because improper lists must fall through" do
      input = """
      defmodule NoLengthGuardImproperListFixture do
        def classify(list) when length(list) > 0, do: :guarded
        def classify(_), do: :fallback
      end
      """

      emitted = fix(NoLengthGuardToPattern, input)

      confirm_fix(emitted, input)

      control = String.replace(input, "NoLengthGuardImproperListFixture", "NoLengthGuardControl")
      fixed = String.replace(emitted, "NoLengthGuardImproperListFixture", "NoLengthGuardFixed")

      program =
        control <>
          fixed <>
          """
          unless NoLengthGuardControl.classify([1 | 2]) ==
                   NoLengthGuardFixed.classify([1 | 2]),
            do: raise("improper-list behavior changed")
          """

      assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(program)
    end

    test "does not rewrite length(list) > 0" do
      code = """
      defmodule Example do
        def process(list) when length(list) > 0 do
          Enum.sum(list)
        end
      end
      """

      confirm_fix(fix(NoLengthGuardToPattern, code), code)
    end

    test "fixes length(list) == 1 into [_] = list pattern" do
      input = """
      defmodule Example do
        def singleton(list) when length(list) == 1 do
          hd(list)
        end
      end
      """

      expected = """
      defmodule Example do
        def singleton([_] = list) do
          hd(list)
        end
      end
      """

      confirm_fix(fix(NoLengthGuardToPattern, input), expected)
    end

    test "fixes length(list) == 3 into [_, _, _] = list pattern" do
      input = """
      defmodule Example do
        defp triplet(list) when length(list) == 3 do
          List.to_tuple(list)
        end
      end
      """

      expected = """
      defmodule Example do
        defp triplet([_, _, _] = list) do
          List.to_tuple(list)
        end
      end
      """

      confirm_fix(fix(NoLengthGuardToPattern, input), expected)
    end

    test "fixes length(list) == 5 into [_, _, _, _, _] = list pattern" do
      input = """
      defmodule Example do
        def five(list) when length(list) == 5 do
          :ok
        end
      end
      """

      expected = """
      defmodule Example do
        def five([_, _, _, _, _] = list) do
          :ok
        end
      end
      """

      confirm_fix(fix(NoLengthGuardToPattern, input), expected)
    end

    test "does not rewrite a compound guard containing length(list) > 0" do
      code = """
      defmodule Example do
        def process(list, x) when length(list) > 0 and is_integer(x) do
          :ok
        end
      end
      """

      confirm_fix(fix(NoLengthGuardToPattern, code), code)
    end

    test "does not rewrite length(list) > 0 on the right of and" do
      code = """
      defmodule Example do
        def process(list, x) when is_atom(x) and length(list) > 0 do
          :ok
        end
      end
      """

      confirm_fix(fix(NoLengthGuardToPattern, code), code)
    end

    test "does not modify when variable is not a direct parameter" do
      code = """
      defmodule Example do
        def process(%{items: list}) when length(list) > 0 do
          :ok
        end
      end
      """

      # Cannot fix — list is nested inside a map pattern, not a top-level param.
      confirm_fix(fix(NoLengthGuardToPattern, code), code)
    end

    test "does not modify length(list) == N for N > 5" do
      code = """
      defmodule Example do
        def check(list) when length(list) == 6 do
          :ok
        end
      end
      """

      confirm_fix(fix(NoLengthGuardToPattern, code), code)
    end

    test "does not modify unfixable patterns like k <= length(nums)" do
      code = """
      defmodule Example do
        def check(nums, k) when k <= length(nums) do
          :ok
        end
      end
      """

      confirm_fix(fix(NoLengthGuardToPattern, code), code)
    end

    test "length(list) > 0 is not reported as fixable" do
      code = """
      defmodule Example do
        def process(list) when length(list) > 0 do
          Enum.sum(list)
        end
      end
      """

      assert check(NoLengthGuardToPattern, code) == []
    end

    test "fixed code has no remaining issues for == N" do
      code = """
      defmodule Example do
        defp triplet(list) when length(list) == 3 do
          List.to_tuple(list)
        end
      end
      """

      assert check(NoLengthGuardToPattern, fix(NoLengthGuardToPattern, code)) == []
    end
  end
end
