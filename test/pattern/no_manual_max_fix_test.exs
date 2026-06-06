defmodule Credence.Pattern.NoManualMaxFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoManualMax

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoManualMax, code, [])
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  describe "fix" do
    test "fixes if a >= b, do: a, else: b" do
      input = """
      defmodule Bad do
        def bigger(a, b) do
          if a >= b, do: a, else: b
        end
      end
      """

      expected = """
      defmodule Bad do
        def bigger(a, b) do
          max(a, b)
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes if b < a, do: a, else: b" do
      input = """
      defmodule Bad do
        def bigger(a, b) do
          if b <= a, do: a, else: b
        end
      end
      """

      expected = """
      defmodule Bad do
        def bigger(a, b) do
          max(a, b)
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes if b <= a, do: a, else: b" do
      input = """
      defmodule Bad do
        def bigger(a, b) do
          if b <= a, do: a, else: b
        end
      end
      """

      expected = """
      defmodule Bad do
        def bigger(a, b) do
          max(a, b)
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes complex expressions" do
      input = """
      new_current = if(current_sum + num >= num, do: current_sum + num, else: num)
      """

      expected = """
      new_current = max(current_sum + num, num)
      """

      assert fix(input) == expected
    end

    test "fixes two complex expressions in same module" do
      input = """
      defmodule Bad do
        def f(current_sum, num, max_sum) do
          new_current = if(current_sum + num >= num, do: current_sum + num, else: num)
          new_max = if(new_current >= max_sum, do: new_current, else: max_sum)
          {new_current, new_max}
        end
      end
      """

      expected = """
      defmodule Bad do
        def f(current_sum, num, max_sum) do
          new_current = max(current_sum + num, num)
          new_max = max(new_current, max_sum)
          {new_current, new_max}
        end
      end
      """

      assert fix(input) == expected
    end

    test "preserves surrounding code" do
      input = """
      defmodule Bad do
        def bigger(a, b, c) do
          result = if a >= b, do: a, else: b
          other = c * 2
          {result, other}
        end
      end
      """

      expected = """
      defmodule Bad do
        def bigger(a, b, c) do
          result = max(a, b)
          other = c * 2
          {result, other}
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes nested max patterns (inner if first)" do
      input = """
      defmodule Bad do
        def f(a, b, c) do
          if (if a >= b, do: a, else: b) >= c, do: (if a >= b, do: a, else: b), else: c
        end
      end
      """

      expected = """
      defmodule Bad do
        def f(a, b, c) do
          max(max(a, b), c)
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes if b > a, do: b, else: a (also a max pattern)" do
      input = """
      def bigger(a, b) do
        if b >= a, do: b, else: a
      end
      """

      expected = """
      def bigger(a, b) do
        max(b, a)
      end
      """

      assert fix(input) == expected
    end

    test "idempotent: running fix twice produces same result" do
      input = """
      defmodule Bad do
        def bigger(a, b) do
          if a >= b, do: a, else: b
        end
      end
      """

      once = fix(input)
      twice = fix(once)
      assert once == twice
    end

    # ---- Negative fix cases: unchanged ----

    test "does not change code with reversed branches (min pattern)" do
      code = """
      def clamp(a, b) do
        if a > b, do: b, else: a
      end
      """

      assert fix(code) == code
    end

    test "does not change code with non-comparison condition" do
      code = """
      def pick(flag, a, b) do
        if flag, do: a, else: b
      end
      """

      assert fix(code) == code
    end

    test "does not change code with mismatched branches" do
      code = """
      def transform(a, b) do
        if a > b, do: a + 1, else: b
      end
      """

      assert fix(code) == code
    end

    test "does not change code with == condition" do
      code = """
      def pick(a, b) do
        if a == b, do: a, else: b
      end
      """

      assert fix(code) == code
    end

    test "does not change code with compound condition" do
      code = """
      def pick(a, b, c) do
        if a > b and a > c, do: a, else: b
      end
      """

      assert fix(code) == code
    end

    test "does not change if without else" do
      code = """
      def maybe(a, b) do
        if a > b, do: a
      end
      """

      assert fix(code) == code
    end

    test "does not change max/2 usage (already correct)" do
      code = """
      def bigger(a, b), do: max(a, b)
      """

      assert fix(code) == code
    end
  end

  describe "fix preserves unrelated formatting" do
    test "does not collapse @doc heredoc into single-line string" do
      input = ~S'''
      defmodule Example do
        @doc """
        Finds the maximum of running sum and global max.

        ## Examples

            iex> Example.step(5, 3)
            5
        """
        @spec step(integer(), integer()) :: integer()
        def step(current_sum, num) do
          new_current = if(current_sum + num >= num, do: current_sum + num, else: num)
          new_current
        end
      end
      '''

      expected = ~S'''
      defmodule Example do
        @doc """
        Finds the maximum of running sum and global max.

        ## Examples

            iex> Example.step(5, 3)
            5
        """
        @spec step(integer(), integer()) :: integer()
        def step(current_sum, num) do
          new_current = max(current_sum + num, num)
          new_current
        end
      end
      '''

      assert fix(input) == expected
    end

    test "does not alter lines outside the if expression" do
      input = ~S'''
      defmodule Example do
        @moduledoc "Example module."

        @doc """
        Computes the larger value.
        """
        @spec pick(integer(), integer()) :: integer()
        def pick(a, b) do
          result = if a >= b, do: a, else: b
          result
        end
      end
      '''

      expected = ~S'''
      defmodule Example do
        @moduledoc "Example module."

        @doc """
        Computes the larger value.
        """
        @spec pick(integer(), integer()) :: integer()
        def pick(a, b) do
          result = max(a, b)
          result
        end
      end
      '''

      assert fix(input) == expected
    end

    test "preserves comment formatting" do
      input = ~S'''
      defmodule Example do
        # This is an important comment
        # that spans multiple lines
        def bigger(a, b) do
          if a >= b, do: a, else: b
        end
      end
      '''

      expected = ~S'''
      defmodule Example do
        # This is an important comment
        # that spans multiple lines
        def bigger(a, b) do
          max(a, b)
        end
      end
      '''

      assert fix(input) == expected
    end
  end
end
