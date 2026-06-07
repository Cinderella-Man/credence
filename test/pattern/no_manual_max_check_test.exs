defmodule Credence.Pattern.NoManualMaxCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoManualMax

  describe "NoManualMax check" do
    test "does not flag strict if a > b, do: a, else: b (value-kind unsafe on ties)" do
      code = """
      defmodule Good do
        def bigger(a, b) do
          if a > b, do: a, else: b
        end
      end
      """

      assert check(NoManualMax, code) == []
    end

    test "detects if a >= b, do: a, else: b" do
      code = """
      defmodule Bad do
        def bigger(a, b) do
          if a >= b, do: a, else: b
        end
      end
      """

      [issue] = check(NoManualMax, code)
      assert issue.message =~ "max/2"
    end

    test "does not flag strict if b < a, do: a, else: b (value-kind unsafe on ties)" do
      code = """
      defmodule Good do
        def bigger(a, b) do
          if b < a, do: a, else: b
        end
      end
      """

      assert check(NoManualMax, code) == []
    end

    test "detects if b <= a, do: a, else: b (flipped with <=)" do
      code = """
      defmodule Bad do
        def bigger(a, b) do
          if b <= a, do: a, else: b
        end
      end
      """

      [issue] = check(NoManualMax, code)
      assert issue.message =~ "max/2"
    end

    test "detects complex expressions (not just variables)" do
      code = """
      defmodule Bad do
        def f(current_sum, num, max_sum) do
          new_current = if(current_sum + num >= num, do: current_sum + num, else: num)
          new_max = if(new_current >= max_sum, do: new_current, else: max_sum)
          {new_current, new_max}
        end
      end
      """

      issues = check(NoManualMax, code)
      assert length(issues) == 2
    end

    test "detects with do/end block syntax" do
      code = """
      defmodule Bad do
        def bigger(a, b) do
          if a >= b do
            a
          else
            b
          end
        end
      end
      """

      [issue] = check(NoManualMax, code)
      assert issue.message =~ "max/2"
    end

    # ---- Negative cases ----
    test "does not flag max/2 usage (already correct)" do
      code = """
      defmodule Good do
        def bigger(a, b), do: max(a, b)
      end
      """

      assert check(NoManualMax, code) == []
    end

    test "does not flag if with unrelated branches" do
      code = """
      defmodule Good do
        def clamp(a, b) do
          if a > b, do: b, else: a
        end
      end
      """

      assert check(NoManualMax, code) == []
    end

    test "does not flag if with non-comparison condition" do
      code = """
      defmodule Good do
        def pick(flag, a, b) do
          if flag, do: a, else: b
        end
      end
      """

      assert check(NoManualMax, code) == []
    end

    test "does not flag if with mismatched branches" do
      code = """
      defmodule Good do
        def transform(a, b) do
          if a > b, do: a + 1, else: b
        end
      end
      """

      assert check(NoManualMax, code) == []
    end

    test "does not flag if without else" do
      code = """
      defmodule Good do
        def maybe(a, b) do
          if a > b, do: a
        end
      end
      """

      assert check(NoManualMax, code) == []
    end

    test "does not flag cond expressions" do
      code = """
      defmodule Good do
        def bigger(a, b) do
          cond do
            a > b -> a
            true -> b
          end
        end
      end
      """

      assert check(NoManualMax, code) == []
    end
  end
end
