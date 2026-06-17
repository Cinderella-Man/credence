defmodule Credence.Pattern.PreferFunctionClausesForListPatternsFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferFunctionClausesForListPatterns

  test "rewrites the anti-pattern" do
    input = """
    defmodule Example do
      @moduledoc false
      def my_fun([], _k), do: 0
      def my_fun(list, k) when is_list(list) and is_integer(k) and k >= 0 do
        case list do
          [] -> 0
          [_single] -> 0
          [h | t] ->
            {min_v, max_v} =
              Enum.reduce(t, {h, h}, fn val, {min_val, max_val} ->
                {min(min_val, val), max(max_val, val)}
              end)

            diff = max_v - min_v
            result = diff - 2 * k
            if result < 0, do: 0, else: result
        end
      end
    end
    """

    expected = """
    defmodule Example do
      @moduledoc false
      def my_fun([], _k), do: 0

      def my_fun([_single], k) when is_integer(k) and k >= 0, do: 0

      def my_fun([h | t], k) when is_integer(k) and k >= 0,
        do:
          (
            {min_v, max_v} =
              Enum.reduce(t, {h, h}, fn val, {min_val, max_val} ->
                {min(min_val, val), max(max_val, val)}
              end)

            diff = max_v - min_v
            result = diff - 2 * k
            if result < 0, do: 0, else: result
          )
    end
    """

    confirm_fix(fix(PreferFunctionClausesForListPatterns, input), expected)
  end

  test "rewrites case with only empty and cons patterns" do
    input = """
    defmodule M do
      def process(list) when is_list(list) do
        case list do
          [] -> :empty
          [h | t] -> {:ok, h, t}
        end
      end
    end
    """

    expected = """
    defmodule M do
      def process([]), do: :empty

      def process([h | t]), do: {:ok, h, t}
    end
    """

    confirm_fix(fix(PreferFunctionClausesForListPatterns, input), expected)
  end

  test "preserves other guards" do
    input = """
    defmodule M do
      def calculate(list, n) when is_list(list) and is_integer(n) do
        case list do
          [] -> 0
          [_] -> n
          [a, b | _] -> a + b + n
        end
      end
    end
    """

    expected = """
    defmodule M do
      def calculate([], n) when is_integer(n), do: 0

      def calculate([_], n) when is_integer(n), do: n

      def calculate([a, b | _], n) when is_integer(n), do: a + b + n
    end
    """

    confirm_fix(fix(PreferFunctionClausesForListPatterns, input), expected)
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OP — dropped (unsafe / out-of-scope) shapes are left untouched
  # ═══════════════════════════════════════════════════════════════════

  test "no-op: case on a parameter without is_list guard" do
    code = """
    defmodule M do
      def process(list) when is_integer(list) do
        case list do
          0 -> :zero
          n -> {:ok, n}
        end
      end
    end
    """

    confirm_fix(fix(PreferFunctionClausesForListPatterns, code), code)
  end

  test "no-op: case on a different variable" do
    code = """
    defmodule M do
      def process(list, other) when is_list(list) do
        case other do
          [] -> :empty
          [h | t] -> {:ok, h}
        end
      end
    end
    """

    confirm_fix(fix(PreferFunctionClausesForListPatterns, code), code)
  end

  test "no-op: non-total case (length >= 2 unmatched)" do
    code = """
    defmodule N do
      def g(list) when is_list(list) do
        case list do
          [] -> :empty
          [_only] -> :one
        end
      end
    end
    """

    confirm_fix(fix(PreferFunctionClausesForListPatterns, code), code)
  end

  # A *guarded* earlier sibling may have its guard fail, so the case branch it
  # appears to cover is still live — the promoted clause must NOT be dropped.
  test "keeps the promoted clause when only a guarded sibling precedes it" do
    input = """
    defmodule M do
      def f([], k) when k < 0, do: :neg
      def f(list, k) when is_list(list) and is_integer(k) do
        case list do
          [] -> :b
          [h | t] -> {:cons, h}
        end
      end
    end
    """

    expected = """
    defmodule M do
      def f([], k) when k < 0, do: :neg

      def f([], k) when is_integer(k), do: :b

      def f([h | t], k) when is_integer(k), do: {:cons, h}
    end
    """

    confirm_fix(fix(PreferFunctionClausesForListPatterns, input), expected)
  end

  # When the body still refers to the original parameter, rebind it in the head.
  test "rebinds the list variable when the body refers to it" do
    input = """
    defmodule B do
      def f(list) when is_list(list) do
        case list do
          [] -> 0
          [_h | _t] -> length(list)
        end
      end
    end
    """

    expected = """
    defmodule B do
      def f([]), do: 0

      def f([_h | _t] = list), do: length(list)
    end
    """

    confirm_fix(fix(PreferFunctionClausesForListPatterns, input), expected)
  end
end
