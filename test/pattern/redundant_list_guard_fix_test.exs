defmodule Credence.Pattern.RedundantListGuardFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.RedundantListGuard

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

      confirm_fix(fix(RedundantListGuard, input), expected)
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

      confirm_fix(fix(RedundantListGuard, input), expected)
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

      confirm_fix(fix(RedundantListGuard, input), expected)
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

      confirm_fix(fix(RedundantListGuard, input), expected)
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

      confirm_fix(fix(RedundantListGuard, input), expected)
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

      confirm_fix(fix(RedundantListGuard, input), expected)
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

      confirm_fix(fix(RedundantListGuard, input), expected)
    end

    test "does not change code without redundant guards" do
      input = """
      defmodule Example do
        def foo(list) when is_list(list), do: list
      end
      """

      confirm_fix(fix(RedundantListGuard, input), input)
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

      confirm_fix(fix(RedundantListGuard, input), expected)
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

      confirm_fix(fix(RedundantListGuard, input), expected)
    end

    test "does not touch functions without cons-tail guards" do
      input = """
      defmodule Example do
        def foo(list) when is_list(list), do: list
        def bar([h | t]), do: {h, t}
      end
      """

      confirm_fix(fix(RedundantListGuard, input), input)
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

      confirm_fix(fix(RedundantListGuard, input), expected)
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

      expected = """
      defmodule Example do
        def foo([h | t]) when is_binary(h) do
          {h, t}
        end
      end
      """

      confirm_fix(fix(RedundantListGuard, input), expected)
    end
  end
end
