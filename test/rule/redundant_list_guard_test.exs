defmodule Credence.Pattern.RedundantListGuardTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.RedundantListGuard.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.RedundantListGuard.fix(code, [])
  end

  describe "RedundantListGuard check" do
    # --- POSITIVE CASES (should flag) ---

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

  describe "fix" do
    test "removes simple is_list guard on cons tail" do
      input = """
      defmodule Example do
        def max_subarray_sum([first | rest]) when is_list(rest) do
          rest
        end
      end
      """

      expected = """
      defmodule Example do
        def max_subarray_sum([first | rest]) do
          rest
        end
      end
      """

      assert fix(input) |> String.trim() == expected |> String.trim()
    end

    test "removes is_list from compound and guard" do
      input = """
      defmodule Example do
        def foo([first | rest]) when is_list(rest) and is_atom(first) do
          rest
        end
      end
      """

      expected = """
      defmodule Example do
        def foo([first | rest]) when is_atom(first) do
          rest
        end
      end
      """

      assert fix(input) |> String.trim() == expected |> String.trim()
    end

    test "removes is_list from compound and guard reversed order" do
      input = """
      defmodule Example do
        def foo([first | rest]) when is_atom(first) and is_list(rest) do
          rest
        end
      end
      """

      expected = """
      defmodule Example do
        def foo([first | rest]) when is_atom(first) do
          rest
        end
      end
      """

      assert fix(input) |> String.trim() == expected |> String.trim()
    end

    test "removes entire when clause when all guards are redundant" do
      input = """
      defmodule Example do
        def merge([h1 | t1], [h2 | t2]) when is_list(t1) and is_list(t2) do
          {t1, t2}
        end
      end
      """

      expected = """
      defmodule Example do
        def merge([h1 | t1], [h2 | t2]) do
          {t1, t2}
        end
      end
      """

      assert fix(input) |> String.trim() == expected |> String.trim()
    end

    test "removes entire when clause for or guard with redundant is_list" do
      input = """
      defmodule Example do
        def foo([first | rest]) when is_list(rest) or is_nil(rest) do
          rest
        end
      end
      """

      expected = """
      defmodule Example do
        def foo([first | rest]) do
          rest
        end
      end
      """

      assert fix(input) |> String.trim() == expected |> String.trim()
    end

    test "handles nested cons pattern" do
      input = """
      defmodule Example do
        def foo({:ok, [h | t]}) when is_list(t) do
          t
        end
      end
      """

      expected = """
      defmodule Example do
        def foo({:ok, [h | t]}) do
          t
        end
      end
      """

      assert fix(input) |> String.trim() == expected |> String.trim()
    end

    test "handles inline do: syntax" do
      input = """
      defmodule Example do
        defp process([_ | tail]) when is_list(tail), do: tail
      end
      """

      expected = """
      defmodule Example do
        defp process([_ | tail]), do: tail
      end
      """

      assert fix(input) |> String.trim() == expected |> String.trim()
    end

    test "does not change code without redundant guards" do
      input = """
      defmodule Example do
        def foo(list) when is_list(list), do: list
      end
      """

      assert fix(input) |> String.trim() == input |> String.trim()
    end

    test "handles longer compound guard with three clauses" do
      input = """
      defmodule Example do
        def foo([first | rest]) when is_list(rest) and is_atom(first) and is_binary(first) do
          rest
        end
      end
      """

      expected = """
      defmodule Example do
        def foo([first | rest]) when is_atom(first) and is_binary(first) do
          rest
        end
      end
      """

      assert fix(input) |> String.trim() == expected |> String.trim()
    end

    test "fixes multiple functions in same module" do
      input = """
      defmodule Example do
        def foo([h | t]) when is_list(t), do: t
        def bar([h | t]) when is_list(t) and is_atom(h), do: {h, t}
      end
      """

      expected = """
      defmodule Example do
        def foo([h | t]), do: t
        def bar([h | t]) when is_atom(h), do: {h, t}
      end
      """

      assert fix(input) |> String.trim() == expected |> String.trim()
    end

    test "does not touch functions without cons-tail guards" do
      input = """
      defmodule Example do
        def foo(list) when is_list(list), do: list
        def bar([h | t]), do: {h, t}
      end
      """

      assert fix(input) |> String.trim() == input |> String.trim()
    end

    test "or with non-redundant side still removes entire guard" do
      # is_list(rest) is always true → the whole `or` is always true
      input = """
      defmodule Example do
        def foo([h | t]) when is_list(t) or is_atom(h) do
          {h, t}
        end
      end
      """

      expected = """
      defmodule Example do
        def foo([h | t]) do
          {h, t}
        end
      end
      """

      assert fix(input) |> String.trim() == expected |> String.trim()
    end

    test "compound or inside and simplifies correctly" do
      # (is_list(t) or is_atom(h)) and is_binary(h)
      # → is_list(t) is always true → or is always true → simplified to is_binary(h)
      input = """
      defmodule Example do
        def foo([h | t]) when (is_list(t) or is_atom(h)) and is_binary(h) do
          {h, t}
        end
      end
      """

      result = fix(input)
      assert result =~ "when is_binary(h)"
      refute result =~ "is_list"
    end
  end
end
