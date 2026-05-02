defmodule Credence.Rule.RedundantListGuardTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.RedundantListGuard.check(ast, [])
  end

  describe "RedundantListGuard" do
    test "detects is_list guard on cons tail in def" do
      code = """
      defmodule Bad do
        def max_subarray_sum([first | rest]) when is_list(rest) do
          rest
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :redundant_list_guard

      assert issue.message =~ "rest"
      assert issue.message =~ "Redundant"
    end

    test "detects is_list guard on cons tail in defp" do
      code = """
      defmodule Bad do
        defp process([_ | tail]) when is_list(tail), do: tail
      end
      """

      [issue] = check(code)
      assert issue.message =~ "tail"
    end

    test "detects redundant is_list inside compound guard with and" do
      code = """
      defmodule Bad do
        def foo([first | rest]) when is_list(rest) and is_atom(first) do
          rest
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "rest"
    end

    test "detects redundant is_list inside compound guard with or" do
      code = """
      defmodule Bad do
        def foo([first | rest]) when is_list(rest) or is_nil(rest) do
          rest
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "rest"
    end

    test "detects redundant is_list inside compound guard with two arguments" do
      code = """
      defmodule Bad do
        def foo(true, [first | rest]) when is_list(rest) and is_atom(first) do
          rest
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "rest"
    end

    test "detects multiple redundant guards across arguments" do
      code = """
      defmodule Bad do
        def merge([h1 | t1], [h2 | t2]) when is_list(t1) and is_list(t2) do
          {t1, t2}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
      names = Enum.map(issues, & &1.message)
      assert Enum.any?(names, &(&1 =~ "t1"))
      assert Enum.any?(names, &(&1 =~ "t2"))
    end

    test "detects guard on nested cons pattern" do
      code = """
      defmodule Bad do
        def foo({:ok, [h | t]}) when is_list(t) do
          t
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "t"
    end

    # ---- Negative cases ----

    test "does not flag is_list on a plain variable (not from cons)" do
      code = """
      defmodule Good do
        def foo(list) when is_list(list), do: list
      end
      """

      assert check(code) == []
    end

    test "does not flag is_list on a first element of a cons pattern" do
      code = """
      defmodule Good do
        def foo([head | tail]) when is_list(head), do: head
      end
      """

      assert check(code) == []
    end

    test "does not flag non-is_list guards on cons tail" do
      code = """
      defmodule Good do
        def foo([h | t]) when is_atom(h), do: {h, t}
      end
      """

      assert check(code) == []
    end

    test "does not flag functions without guards" do
      code = """
      defmodule Good do
        def foo([h | t]), do: {h, t}
      end
      """

      assert check(code) == []
    end

    test "does not flag functions without cons patterns" do
      code = """
      defmodule Good do
        def foo(a, b) when is_integer(a), do: a + b
      end
      """

      assert check(code) == []
    end

    test "does not flag is_list on head variable" do
      code = """
      defmodule Good do
        def foo([head | _]) when is_list(head), do: head
      end
      """

      assert check(code) == []
    end
  end
end
