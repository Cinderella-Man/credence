defmodule Credence.Pattern.NoManualMaxTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoManualMax.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoManualMax.fix(code, []) |> String.trim_trailing()
  end

  defp ast_of(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    ast
  end

  # Semantic comparison: strips metadata so formatting differences don't matter
  defp strip_meta({form, _meta, args}) do
    {strip_meta(form), nil, strip_meta(args)}
  end

  defp strip_meta(list) when is_list(list), do: Enum.map(list, &strip_meta/1)
  defp strip_meta({a, b}), do: {strip_meta(a), strip_meta(b)}
  defp strip_meta(other), do: other

  defp assert_semantically_equal(fixed, expected) do
    assert strip_meta(ast_of(fixed)) == strip_meta(ast_of(expected))
  end

  describe "NoManualMax" do
    test "detects if a > b, do: a, else: b" do
      code = """
      defmodule Bad do
        def bigger(a, b) do
          if a > b, do: a, else: b
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_manual_max
      assert issue.message =~ "max/2"
    end

    test "detects if a >= b, do: a, else: b" do
      code = """
      defmodule Bad do
        def bigger(a, b) do
          if a >= b, do: a, else: b
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "max/2"
    end

    test "detects if b < a, do: a, else: b (flipped comparison)" do
      code = """
      defmodule Bad do
        def bigger(a, b) do
          if b < a, do: a, else: b
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "max/2"
    end

    test "detects if b <= a, do: a, else: b (flipped with <=)" do
      code = """
      defmodule Bad do
        def bigger(a, b) do
          if b <= a, do: a, else: b
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "max/2"
    end

    test "detects complex expressions (not just variables)" do
      code = """
      defmodule Bad do
        def f(current_sum, num, max_sum) do
          new_current = if(current_sum + num > num, do: current_sum + num, else: num)
          new_max = if(new_current > max_sum, do: new_current, else: max_sum)
          {new_current, new_max}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end

    test "detects with do/end block syntax" do
      code = """
      defmodule Bad do
        def bigger(a, b) do
          if a > b do
            a
          else
            b
          end
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "max/2"
    end

    # ---- Negative cases ----
    test "does not flag max/2 usage (already correct)" do
      code = """
      defmodule Good do
        def bigger(a, b), do: max(a, b)
      end
      """

      assert check(code) == []
    end

    test "does not flag if with unrelated branches" do
      code = """
      defmodule Good do
        def clamp(a, b) do
          if a > b, do: b, else: a
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag if with non-comparison condition" do
      code = """
      defmodule Good do
        def pick(flag, a, b) do
          if flag, do: a, else: b
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag if with mismatched branches" do
      code = """
      defmodule Good do
        def transform(a, b) do
          if a > b, do: a + 1, else: b
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag if without else" do
      code = """
      defmodule Good do
        def maybe(a, b) do
          if a > b, do: a
        end
      end
      """

      assert check(code) == []
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

      assert check(code) == []
    end
  end

  describe "fix" do
    test "fixes if a > b, do: a, else: b" do
      code = """
      defmodule Bad do
        def bigger(a, b) do
          if a > b, do: a, else: b
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "max(a, b)"
      refute fixed =~ "if"
    end

    test "fixes if a >= b, do: a, else: b" do
      code = """
      defmodule Bad do
        def bigger(a, b) do
          if a >= b, do: a, else: b
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "max(a, b)"
      refute fixed =~ "if"
    end

    test "fixes if b < a, do: a, else: b" do
      code = """
      defmodule Bad do
        def bigger(a, b) do
          if b < a, do: a, else: b
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "max(a, b)"
      refute fixed =~ "if"
    end

    test "fixes if b <= a, do: a, else: b" do
      code = """
      defmodule Bad do
        def bigger(a, b) do
          if b <= a, do: a, else: b
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "max(a, b)"
      refute fixed =~ "if"
    end

    test "fixes complex expressions" do
      code = "new_current = if(current_sum + num > num, do: current_sum + num, else: num)"

      fixed = fix(code)
      assert fixed =~ "max(current_sum + num, num)"
      refute fixed =~ "if"
    end

    test "fixes two complex expressions in same module" do
      code = """
      defmodule Bad do
        def f(current_sum, num, max_sum) do
          new_current = if(current_sum + num > num, do: current_sum + num, else: num)
          new_max = if(new_current > max_sum, do: new_current, else: max_sum)
          {new_current, new_max}
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "max(current_sum + num, num)"
      assert fixed =~ "max(new_current, max_sum)"
      refute fixed =~ "if"
    end

    test "preserves surrounding code" do
      code = """
      defmodule Bad do
        def bigger(a, b, c) do
          result = if a > b, do: a, else: b
          other = c * 2
          {result, other}
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "max(a, b)"
      assert fixed =~ "c * 2"
      assert fixed =~ "{result, other}"
    end

    test "fixes nested max patterns (inner if first)" do
      code = """
      defmodule Bad do
        def f(a, b, c) do
          if (if a > b, do: a, else: b) > c, do: (if a > b, do: a, else: b), else: c
        end
      end
      """

      fixed = fix(code)
      # Inner ifs become max(a, b), then outer condition is max(a,b) > c
      # with do: max(a,b), else: c → max(max(a, b), c)
      assert fixed =~ "max("
      refute fixed =~ "if"
    end

    test "idempotent: running fix twice produces same result" do
      code = """
      defmodule Bad do
        def bigger(a, b) do
          if a > b, do: a, else: b
        end
      end
      """

      once = fix(code)
      twice = fix(once)
      assert once == twice
    end

    # ---- Negative fix cases: semantically unchanged ----

    test "does not change code with reversed branches (min pattern)" do
      code = """
      def clamp(a, b) do
        if a > b, do: b, else: a
      end
      """

      fixed = fix(code)
      assert_semantically_equal(fixed, code)
    end

    test "does not change code with non-comparison condition" do
      code = """
      def pick(flag, a, b) do
        if flag, do: a, else: b
      end
      """

      fixed = fix(code)
      assert_semantically_equal(fixed, code)
    end

    test "does not change code with mismatched branches" do
      code = """
      def transform(a, b) do
        if a > b, do: a + 1, else: b
      end
      """

      fixed = fix(code)
      assert_semantically_equal(fixed, code)
    end

    test "does not change code with == condition" do
      code = """
      def pick(a, b) do
        if a == b, do: a, else: b
      end
      """

      fixed = fix(code)
      assert_semantically_equal(fixed, code)
    end

    test "does not change code with compound condition" do
      code = """
      def pick(a, b, c) do
        if a > b and a > c, do: a, else: b
      end
      """

      fixed = fix(code)
      assert_semantically_equal(fixed, code)
    end

    test "does not change if without else" do
      code = """
      def maybe(a, b) do
        if a > b, do: a
      end
      """

      fixed = fix(code)
      assert_semantically_equal(fixed, code)
    end

    test "does not change max/2 usage (already correct)" do
      code = """
      def bigger(a, b), do: max(a, b)
      """

      fixed = fix(code)
      assert_semantically_equal(fixed, code)
    end

    test "fixes if b > a, do: b, else: a (also a max pattern)" do
      code = """
      def bigger(a, b) do
        if b > a, do: b, else: a
      end
      """

      fixed = fix(code)
      assert fixed =~ "max(b, a)"
      refute fixed =~ "if"
    end
  end
end
