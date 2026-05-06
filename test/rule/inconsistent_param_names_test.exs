defmodule Credence.Pattern.InconsistentParamNamesTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.InconsistentParamNames.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.InconsistentParamNames.fix(code, [])
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

      [issue, issue2] = check(code)
      assert issue.rule == :inconsistent_param_names
      assert issue.message =~ "current"
      assert issue.message =~ "prev"
      assert issue.message =~ "position 1"
      assert issue2.rule == :inconsistent_param_names
      assert issue2.message =~ "current"
      assert issue2.message =~ "next"
      assert issue2.message =~ "position 2"
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

      issues = check(code)
      assert length(issues) == 2
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

    test "flags _number vs banana as inconsistent (base name number vs banana)" do
      code = """
      defmodule Bad do
        def process(_number, opts), do: opts
        def process(banana, opts), do: {banana, opts}
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).message =~ "position 1"
    end

    test "does not flag _number vs number (same base name)" do
      code = """
      defmodule Bad do
        def process(_number, opts), do: opts
        def process(number, opts), do: {number, opts}
      end
      """

      assert check(code) == []
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

      assert check(code) == []
    end

    test "does not flag underscore-prefixed variables with matching base" do
      code = """
      defmodule Good do
        defp process(data, _opts), do: data
        defp process(input, opts), do: {input, opts}
      end
      """

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

      assert check(code) == []
    end

    test "does not flag pinned variables" do
      code = """
      defmodule Good do
        def match(^expected, val), do: val
        def match(other, val), do: {other, val}
      end
      """

      assert check(code) == []
    end

    test "does not flag bare _ (always skips position)" do
      code = """
      defmodule Good do
        def process(_, opts), do: opts
        def process(banana, opts), do: {banana, opts}
      end
      """

      assert check(code) == []
    end
  end

  describe "fix/2 — basic renaming" do
    test "renames second clause params to match first clause" do
      code = """
      defmodule Bad do
        def process(input, count), do: {input, count}
        def process(data, n), do: {data, n}
      end
      """

      result = fix(code)

      # Both clauses should use first clause's names
      assert result =~ "def process(input, count)"
      refute result =~ "data"
      refute result =~ ", n)"
    end

    test "renames variables in the body too" do
      code = """
      defmodule Bad do
        def transform(val), do: val + 1
        def transform(x), do: x * 2
      end
      """

      result = fix(code)

      # Second clause body should use `val`, not `x`
      assert result =~ "val * 2"
      refute result =~ "x"
    end

    test "renames across three clauses" do
      code = """
      defmodule Bad do
        def transform(val, opts), do: {val, opts}
        def transform(value, options), do: {value, options}
        def transform(x, config), do: {x, config}
      end
      """

      result = fix(code)

      refute result =~ "value"
      refute result =~ "options"
      refute result =~ "(x,"
      refute result =~ "config"
    end
  end

  describe "fix/2 — underscore prefix preservation" do
    test "preserves underscore prefix when renaming" do
      code = """
      defmodule Bad do
        def process(number, _opts), do: number
        def process(banana, _config), do: banana
      end
      """

      result = fix(code)

      # Second clause: _config should become _opts (preserving underscore)
      assert result =~ "_opts"
      refute result =~ "_config"
      refute result =~ "banana"
    end

    test "first clause underscore establishes canonical base name" do
      code = """
      defmodule Bad do
        def process(_number, opts), do: opts
        def process(banana, opts), do: {banana, opts}
      end
      """

      result = fix(code)

      # Canonical base is "number", second clause's banana → number
      assert result =~ "number"
      refute result =~ "banana"
    end
  end

  describe "fix/2 — guards and complex clauses" do
    test "renames in guarded clauses" do
      code = """
      defmodule Bad do
        defp loop(num, divisor) when rem(num, divisor) == 0 do
          loop(div(num, divisor), divisor)
        end

        defp loop(n, i) when i * i <= n do
          loop(n, i + 1)
        end
      end
      """

      result = fix(code)

      # Second clause should use num and divisor (matching first clause)
      # In guard and body
      refute result =~ ~r/\bn\b/
      refute result =~ ~r/\bi\b/
    end

    test "renames in function body including recursive calls" do
      code = """
      defmodule Bad do
        defp helper(alpha, beta, gamma), do: {alpha, beta, gamma}
        defp helper(first, second, third), do: helper(first, second, third)
      end
      """

      result = fix(code)

      # Recursive call should also be renamed
      assert result =~ "helper(alpha, beta, gamma)"
      refute result =~ "first"
      refute result =~ "second"
      refute result =~ "third"
    end
  end

  describe "fix/2 — skipped positions" do
    test "does not rename positions with patterns or literals" do
      code = """
      defmodule Good do
        def factorial(0, acc), do: acc
        def factorial(n, acc), do: factorial(n - 1, n * acc)
      end
      """

      result = fix(code)

      # Position 1 has literal 0, so skipped — n stays n
      assert result =~ "factorial(n, acc)"
    end

    test "does not rename bare underscore positions" do
      code = """
      defmodule Fine do
        def handle(_, value), do: value
        def handle(thing, data), do: {thing, data}
      end
      """

      result = fix(code)

      # Position 1 is bare _ in clause 1, so skipped
      # Position 2: value is canonical, data → value
      assert result =~ "thing"
      refute result =~ "data"
    end
  end

  describe "fix/2 — edge cases and no-ops" do
    test "returns valid code when nothing to fix" do
      code = """
      defmodule Good do
        defp do_fibonacci(prev, _current, 0), do: prev
        defp do_fibonacci(prev, current, steps), do: do_fibonacci(current, prev + current, steps - 1)
      end
      """

      result = fix(code)
      assert {:ok, _} = Code.string_to_quoted(result)
    end

    test "does not touch single-clause functions" do
      code = """
      defmodule Good do
        defp helper(data, count), do: {data, count}
      end
      """

      result = fix(code)
      assert result =~ "data"
      assert result =~ "count"
    end

    test "does not touch separate functions in same module" do
      code = """
      defmodule Good do
        def process(data), do: data
        def transform(input), do: input
      end
      """

      result = fix(code)
      assert result =~ "data"
      assert result =~ "input"
    end

    test "round-trip: fixed code produces zero issues" do
      code = """
      defmodule Bad do
        defp helper(alpha, beta, gamma), do: {alpha, beta, gamma}
        defp helper(first, second, third), do: {first, second, third}
      end
      """

      fixed = fix(code)
      {:ok, ast} = Code.string_to_quoted(fixed)
      assert [] == Credence.Pattern.InconsistentParamNames.check(ast, [])
    end

    test "round-trip: fibonacci example" do
      code = """
      defmodule Bad do
        defp do_fibonacci(current, _next, 0), do: current
        defp do_fibonacci(prev, current, steps), do: do_fibonacci(current, prev + current, steps - 1)
      end
      """

      fixed = fix(code)
      {:ok, ast} = Code.string_to_quoted(fixed)
      assert [] == Credence.Pattern.InconsistentParamNames.check(ast, [])
    end

    test "fixed code is always valid Elixir" do
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

      fixed = fix(code)
      assert {:ok, _} = Code.string_to_quoted(fixed)
    end
  end
end
