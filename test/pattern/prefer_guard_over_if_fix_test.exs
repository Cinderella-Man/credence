defmodule Credence.Pattern.PreferGuardOverIfFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferGuardOverIf

  # ═══════════════════════════════════════════════════════════════════
  # SAFE CORE — rewritten into two guarded clauses
  # ═══════════════════════════════════════════════════════════════════

  test "comparison operator" do
    code = """
    defp check(x) do
      if x > 0 do
        :positive
      else
        :non_positive
      end
    end
    """

    expected = """
    defp check(x) when x > 0 do
      :positive
    end
    defp check(_x) do
      :non_positive
    end
    """

    assert fix(PreferGuardOverIf, code) == expected
  end

  test "is_nil type-check guard" do
    code = """
    defp check(val, default) do
      if is_nil(val) do
        default
      else
        val
      end
    end
    """

    expected = """
    defp check(val, default) when is_nil(val) do
      default
    end
    defp check(val, _default) do
      val
    end
    """

    assert fix(PreferGuardOverIf, code) == expected
  end

  test "preserves and combines an existing guard" do
    code = """
    defp check(x) when is_integer(x) do
      if x > 0 do
        :positive
      else
        :non_positive
      end
    end
    """

    expected = """
    defp check(x) when is_integer(x) and x > 0 do
      :positive
    end
    defp check(x) when is_integer(x) do
      :non_positive
    end
    """

    assert fix(PreferGuardOverIf, code) == expected
  end

  test "keyword-syntax if" do
    code = """
    defp check(x) do
      if x > 0, do: :positive, else: :non_positive
    end
    """

    expected = """
    defp check(x) when x > 0 do
      :positive
    end
    defp check(_x) do
      :non_positive
    end
    """

    assert fix(PreferGuardOverIf, code) == expected
  end

  test "underscores params unused in each clause" do
    code = """
    defp classify(x, y) do
      if x > 0 do
        :positive
      else
        y
      end
    end
    """

    expected = """
    defp classify(x, _y) when x > 0 do
      :positive
    end
    defp classify(_x, y) do
      y
    end
    """

    assert fix(PreferGuardOverIf, code) == expected
  end

  test "underscores all params in a constant catch-all clause" do
    code = """
    defp find_position(matrix, target, low, high) do
      if low <= high do
        do_search(matrix, target, low, high)
      else
        false
      end
    end
    """

    expected = """
    defp find_position(matrix, target, low, high) when low <= high do
      do_search(matrix, target, low, high)
    end
    defp find_position(_matrix, _target, _low, _high) do
      false
    end
    """

    assert fix(PreferGuardOverIf, code) == expected
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OP — left untouched (unsafe or undesirable to rewrite)
  # ═══════════════════════════════════════════════════════════════════

  test "equality with a literal is left alone (prefer pattern matching)" do
    code = """
    defp check(x) do
      if x == 0 do
        :zero
      else
        :non_zero
      end
    end
    """

    assert fix(PreferGuardOverIf, code) == code
  end

  test "arithmetic condition is left alone (rem can raise; guard would swallow it)" do
    code = """
    defp classify(x, y) do
      if rem(x, y) == 0 do
        :divisible
      else
        :not_divisible
      end
    end
    """

    assert fix(PreferGuardOverIf, code) == code
  end

  test "`not` over a bare variable is left alone (truthiness/raise mismatch)" do
    code = """
    defp check(flag) do
      if not flag do
        :off
      else
        :on
      end
    end
    """

    assert fix(PreferGuardOverIf, code) == code
  end

  test "bare-variable condition is left alone (truthiness mismatch)" do
    code = """
    defp check(flag) do
      if flag do
        :on
      else
        :off
      end
    end
    """

    assert fix(PreferGuardOverIf, code) == code
  end

  test "local function call in condition is left alone" do
    code = """
    defp check(x) do
      if valid?(x) do
        :ok
      else
        :error
      end
    end
    """

    assert fix(PreferGuardOverIf, code) == code
  end

  test "remote function call in condition is left alone" do
    code = """
    defp check(list) do
      if Enum.empty?(list) do
        :empty
      else
        hd(list)
      end
    end
    """

    assert fix(PreferGuardOverIf, code) == code
  end
end
