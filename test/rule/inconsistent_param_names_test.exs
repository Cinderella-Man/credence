defmodule Credence.Rule.InconsistentParamNamesTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.InconsistentParamNames.check(ast, [])
  end

  describe "InconsistentParamNames" do
    test "detects name drift in do_fibonacci (current vs prev)" do
      code = """
      defmodule Bad do
        defp do_fibonacci(current, _next, 0), do: current

        defp do_fibonacci(prev, current, steps) do
          do_fibonacci(current, prev + current, steps - 1)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :inconsistent_param_names
      assert issue.severity == :warning
      assert issue.message =~ "current"
      assert issue.message =~ "prev"
      assert issue.message =~ "position 1"
    end

    test "detects inconsistency in def (not just defp)" do
      code = """
      defmodule Bad do
        def process(input, count), do: {input, count}
        def process(data, n), do: {data, n}
      end
      """

      issues = check(code)
      assert length(issues) == 2

      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &(&1 =~ "position 1"))
      assert Enum.any?(messages, &(&1 =~ "position 2"))
    end

    test "detects drift in guarded clauses" do
      code = """
      defmodule Bad do
        defp loop(num, divisor) when rem(num, divisor) == 0 do
          loop(div(num, divisor), divisor)
        end

        defp loop(n, i) when i * i <= n do
          loop(n, i + 1)
        end

        defp loop(n, _i), do: n
      end
      """

      # Position 1: num vs n — flagged
      # Position 2: divisor vs i vs _i — _i is underscore so skipped
      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).message =~ "position 1"
    end

    test "detects multiple positions with drift" do
      code = """
      defmodule Bad do
        defp helper(alpha, beta, gamma), do: {alpha, beta, gamma}
        defp helper(first, second, third), do: {first, second, third}
      end
      """

      issues = check(code)
      assert length(issues) == 3
    end

    test "detects drift across three clauses" do
      code = """
      defmodule Bad do
        def transform(val, opts), do: {val, opts}
        def transform(value, options), do: {value, options}
        def transform(x, config), do: {x, config}
      end
      """

      issues = check(code)
      assert length(issues) == 2

      pos1 = Enum.find(issues, &(&1.message =~ "position 1"))
      assert pos1.message =~ "val"
      assert pos1.message =~ "value"
      assert pos1.message =~ "x"
    end

    test "detects drift when one clause is guarded and another is not" do
      code = """
      defmodule Bad do
        defp do_largest_cont_sum(list, current, best) when is_list(list) do
          {list, current, best}
        end

        defp do_largest_cont_sum(nums, curr_sum, max_sum) do
          {nums, curr_sum, max_sum}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 3
    end

    # ---- Negative cases ----

    test "does not flag consistent names" do
      code = """
      defmodule Good do
        defp do_fibonacci(prev, _current, 0), do: prev

        defp do_fibonacci(prev, current, steps) do
          do_fibonacci(current, prev + current, steps - 1)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when patterns differ (legitimate dispatch)" do
      code = """
      defmodule Good do
        def handle({:ok, result}), do: result
        def handle({:error, reason}), do: raise reason
      end
      """

      assert check(code) == []
    end

    test "does not flag when literals are used (pattern matching)" do
      code = """
      defmodule Good do
        def factorial(0, acc), do: acc
        def factorial(n, acc), do: factorial(n - 1, n * acc)
      end
      """

      # Position 1: 0 vs n — 0 is a literal, so position is skipped
      assert check(code) == []
    end

    test "does not flag underscore-prefixed variables" do
      code = """
      defmodule Good do
        defp process(data, _opts), do: data
        defp process(input, opts), do: {input, opts}
      end
      """

      # Position 1: data vs input — flagged
      # Position 2: _opts vs opts — _opts is underscore, skip
      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).message =~ "position 1"
    end

    test "does not flag single-clause functions" do
      code = """
      defmodule Good do
        defp helper(data, count), do: {data, count}
      end
      """

      assert check(code) == []
    end

    test "does not flag different functions that share names" do
      code = """
      defmodule Good do
        def process(data), do: data
        def transform(input), do: input
      end
      """

      assert check(code) == []
    end

    test "does not flag functions with different arities" do
      code = """
      defmodule Good do
        def foo(alpha), do: alpha
        def foo(first, second), do: {first, second}
      end
      """

      assert check(code) == []
    end

    test "does not flag list/cons patterns at a position" do
      code = """
      defmodule Good do
        def count([], acc), do: acc
        def count([_h | t], acc), do: count(t, acc + 1)
      end
      """

      assert check(code) == []
    end

    test "does not flag map/struct patterns at a position" do
      code = """
      defmodule Good do
        def get(%{key: val}, default), do: val || default
        def get(container, default), do: {container, default}
      end
      """

      # Position 1: map pattern vs simple var — skipped
      assert check(code) == []
    end

    test "does not flag pinned variables" do
      code = """
      defmodule Good do
        def match(^expected, val), do: val
        def match(other, val), do: {other, val}
      end
      """

      # Position 1: ^expected is a pin, not a simple var — skipped
      assert check(code) == []
    end
  end
end
