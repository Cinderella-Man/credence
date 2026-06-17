defmodule Credence.Pattern.NoCaseOnParamDispatchFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoCaseOnParamDispatch

  # ═══════════════════════════════════════════════════════════════════
  # REWRITES — case-on-param → multi-clause function heads
  # ═══════════════════════════════════════════════════════════════════

  test "literal + variable catch-all" do
    code = """
    def run(x) do
      case x do
        0 -> :zero
        n -> {:ok, n}
      end
    end
    """

    expected = """
    def run(0), do: :zero
    def run(n), do: {:ok, n}
    """

    confirm_fix(fix(NoCaseOnParamDispatch, code), expected)
  end

  test "list patterns, catch-all body refers to the parameter (kept as the bare var)" do
    code = """
    def pick_coins(coins) do
      case coins do
        [] -> 0
        [first] -> first
        [first, second] -> max(first, second)
        _ -> do_pick_coins(coins, 0, 0)
      end
    end
    """

    expected = """
    def pick_coins([]), do: 0
    def pick_coins([first]), do: first
    def pick_coins([first, second]), do: max(first, second)
    def pick_coins(coins), do: do_pick_coins(coins, 0, 0)
    """

    confirm_fix(fix(NoCaseOnParamDispatch, code), expected)
  end

  test "map patterns and a defp" do
    code = """
    def handle(msg) do
      case msg do
        %{type: :ping} -> :pong
        %{type: :data, payload: p} -> process(p)
        _ -> :unknown
      end
    end
    """

    expected = """
    def handle(%{type: :ping}), do: :pong
    def handle(%{type: :data, payload: p}), do: process(p)
    def handle(_), do: :unknown
    """

    confirm_fix(fix(NoCaseOnParamDispatch, code), expected)
  end

  test "clause guards are preserved as head guards" do
    code = """
    defp classify(x) do
      case x do
        0 -> :zero
        n when n > 0 -> :positive
        _ -> :negative
      end
    end
    """

    expected = """
    defp classify(0), do: :zero
    defp classify(n) when n > 0, do: :positive
    defp classify(_), do: :negative
    """

    confirm_fix(fix(NoCaseOnParamDispatch, code), expected)
  end

  test "catch-all bound variable equal to the subject is used as-is" do
    code = """
    def last(list) do
      case list do
        [] -> nil
        list -> List.last(list)
      end
    end
    """

    expected = """
    def last([]), do: nil
    def last(list), do: List.last(list)
    """

    confirm_fix(fix(NoCaseOnParamDispatch, code), expected)
  end

  test "literal clause whose body refers to the parameter keeps it via `pattern = v`" do
    code = """
    def f(x) do
      case x do
        0 -> x + 1
        n -> n
      end
    end
    """

    expected = """
    def f(0 = x), do: x + 1
    def f(n), do: n
    """

    confirm_fix(fix(NoCaseOnParamDispatch, code), expected)
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OP — dropped (unsafe / out-of-scope) shapes are left untouched
  # ═══════════════════════════════════════════════════════════════════

  test "no-op: tuple / multi-parameter dispatch" do
    code = """
    def gcd(x, y) do
      case {x, y} do
        {0, y} -> y
        {x, 0} -> x
        _ -> gcd(y, rem(x, y))
      end
    end
    """

    confirm_fix(fix(NoCaseOnParamDispatch, code), code)
  end

  test "no-op: non-total case (no catch-all)" do
    code = """
    def f(x) do
      case x do
        0 -> :a
        1 -> :b
      end
    end
    """

    confirm_fix(fix(NoCaseOnParamDispatch, code), code)
  end

  test "no-op: function-head guard" do
    code = """
    def f(x) when is_integer(x) do
      case x do
        0 -> :zero
        _ -> :other
      end
    end
    """

    confirm_fix(fix(NoCaseOnParamDispatch, code), code)
  end

  test "no-op: pinned pattern" do
    code = """
    def f(x) do
      case x do
        ^x -> :same
        _ -> :other
      end
    end
    """

    confirm_fix(fix(NoCaseOnParamDispatch, code), code)
  end
end
