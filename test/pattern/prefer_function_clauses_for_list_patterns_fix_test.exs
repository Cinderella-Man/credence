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

    assert fix(PreferFunctionClausesForListPatterns, input) == expected
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

    assert fix(PreferFunctionClausesForListPatterns, input) == expected
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

    assert fix(PreferFunctionClausesForListPatterns, input) == expected
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

    assert fix(PreferFunctionClausesForListPatterns, code) == code
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

    assert fix(PreferFunctionClausesForListPatterns, code) == code
  end
end
