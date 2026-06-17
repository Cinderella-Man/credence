defmodule Credence.Semantic.PreferKernelMaxOverLocalFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.PreferKernelMaxOverLocal

  defp fix(source, message, line \\ 1) do
    PreferKernelMaxOverLocal.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  @max_msg "imported Kernel.max/2 conflicts with local function"
  @min_msg "imported Kernel.min/2 conflicts with local function"

  test "removes canonical defp max/2 and qualifies calls to Kernel.max/2" do
    input = """
    defmodule Solution do
      def calculate do
        max(3, 5)
      end

      defp max(a, b) when a >= b, do: a
      defp max(a, b) when b > a, do: b
    end
    """

    expected = """
    defmodule Solution do
      def calculate do
        Kernel.max(3, 5)
      end
    end
    """

    confirm_fix(fix(input, @max_msg), expected)
  end

  test "removes canonical defp min/2 and qualifies calls to Kernel.min/2" do
    input = """
    defmodule Solution do
      def calculate do
        min(3, 5)
      end

      defp min(a, b) when a <= b, do: a
      defp min(a, b) when b < a, do: b
    end
    """

    expected = """
    defmodule Solution do
      def calculate do
        Kernel.min(3, 5)
      end
    end
    """

    confirm_fix(fix(input, @min_msg), expected)
  end

  test "canonical max fix output is well-formed (parses)" do
    input = """
    defmodule Solution do
      def calculate do
        max(3, 5)
      end

      defp max(a, b) when a >= b, do: a
      defp max(a, b) when b > a, do: b
    end
    """

    assert valid_syntax?(fix(input, @max_msg))
  end

  # --- deliberately left untouched (no safe same-answer fix) ------------------

  test "leaves a local max/2 with a non-canonical body alone" do
    # `a * b` is not `Kernel.max/2`; deleting it and redirecting to Kernel.max
    # would change the answer (15 vs 5), so the rule must not touch it.
    input = """
    defmodule Solution do
      def calculate do
        max(3, 5)
      end

      defp max(a, b), do: a * b
    end
    """

    confirm_fix(fix(input, @max_msg), input)
  end

  test "leaves a swapped-operator max/2 alone (tie case diverges from Kernel)" do
    # Here the `>=` clause returns the SECOND param, so `max(1, 1.0)` would
    # return 1.0 while Kernel.max(1, 1.0) returns 1 — not the same answer.
    input = """
    defmodule Solution do
      def calculate do
        max(3, 5)
      end

      defp max(a, b) when a > b, do: a
      defp max(a, b) when b >= a, do: b
    end
    """

    confirm_fix(fix(input, @max_msg), input)
  end

  test "leaves a canonical max/2 referenced by an &max/2 capture alone" do
    input = """
    defmodule Solution do
      def calculate do
        Enum.reduce([1, 2], &max/2)
      end

      defp max(a, b) when a >= b, do: a
      defp max(a, b) when b > a, do: b
    end
    """

    confirm_fix(fix(input, @max_msg), input)
  end

  test "leaves a canonical max/2 reached through a pipe alone" do
    input = """
    defmodule Solution do
      def calculate do
        3 |> max(5)
      end

      defp max(a, b) when a >= b, do: a
      defp max(a, b) when b > a, do: b
    end
    """

    confirm_fix(fix(input, @max_msg), input)
  end

  test "leaves a canonical max/2 alone when a same-name sibling of another arity exists" do
    input = """
    defmodule Solution do
      def calculate do
        max(3, 5)
      end

      defp max(a), do: a
      defp max(a, b) when a >= b, do: a
      defp max(a, b) when b > a, do: b
    end
    """

    confirm_fix(fix(input, @max_msg), input)
  end

  test "leaves is_nil/1 alone (outside the safe core)" do
    input = """
    defmodule Problematic do
      defp is_nil(nil), do: true
      defp is_nil(_other), do: false

      def check_value(map, key) do
        value = Map.get(map, key)

        if is_nil(value) do
          :missing
        else
          {:ok, value}
        end
      end
    end
    """

    confirm_fix(fix(input, "imported Kernel.is_nil/1 conflicts with local function"), input)
  end
end
