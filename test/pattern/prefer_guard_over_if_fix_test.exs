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

    confirm_fix(fix(PreferGuardOverIf, code), expected)
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

    confirm_fix(fix(PreferGuardOverIf, code), expected)
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

    confirm_fix(fix(PreferGuardOverIf, code), expected)
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

    confirm_fix(fix(PreferGuardOverIf, code), expected)
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

    confirm_fix(fix(PreferGuardOverIf, code), expected)
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

    confirm_fix(fix(PreferGuardOverIf, code), expected)
  end

  test "var == var equality uses when guard (Compress regression)" do
    code = """
    defmodule Compress do
      def process([], _index, result, current_char, count) do
        result <> Integer.to_string(count)
      end

      def process([current_char | rest], index, result, prev_char, count) do
        if current_char == prev_char do
          process(rest, index + 1, result, prev_char, count + 1)
        else
          new_result = result <> prev_char <> Integer.to_string(count)
          process(rest, index + 1, new_result, current_char, 1)
        end
      end
    end
    """

    expected = """
    defmodule Compress do
      def process([], _index, result, current_char, count) do
        result <> Integer.to_string(count)
      end

      def process([current_char | rest], index, result, prev_char, count)
          when current_char == prev_char do
        process(rest, index + 1, result, prev_char, count + 1)
      end
      def process([current_char | rest], index, result, prev_char, count) do
        new_result = result <> prev_char <> Integer.to_string(count)
        process(rest, index + 1, new_result, current_char, 1)
      end
    end
    """

    confirm_fix(fix(PreferGuardOverIf, code), expected)
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OP — left untouched (unsafe or undesirable to rewrite)
  # ═══════════════════════════════════════════════════════════════════

  test "var == var equality with and in condition uses when guard (knight_moves regression)" do
    code = """
    defmodule Solution do
      defp bfs_step([], _visited, _target_x, _target_y), do: 0

      defp bfs_step([{cx, cy, moves} | rest], visited, target_x, target_y) do
        if cx == target_x and cy == target_y do
          moves
        else
          possible_moves = []
          new_queue = []
          bfs_step(new_queue, visited, target_x, target_y)
        end
      end
    end
    """

    expected = """
    defmodule Solution do
      defp bfs_step([], _visited, _target_x, _target_y), do: 0

      defp bfs_step([{cx, cy, moves} | _rest], _visited, target_x, target_y)
           when cx == target_x and cy == target_y do
        moves
      end
      defp bfs_step([{_cx, _cy, _moves} | _rest], visited, target_x, target_y) do
        possible_moves = []
        new_queue = []
        bfs_step(new_queue, visited, target_x, target_y)
      end
    end
    """

    confirm_fix(fix(PreferGuardOverIf, code), expected)
  end

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

    confirm_fix(fix(PreferGuardOverIf, code), code)
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

    confirm_fix(fix(PreferGuardOverIf, code), code)
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

    confirm_fix(fix(PreferGuardOverIf, code), code)
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

    confirm_fix(fix(PreferGuardOverIf, code), code)
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

    confirm_fix(fix(PreferGuardOverIf, code), code)
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

    confirm_fix(fix(PreferGuardOverIf, code), code)
  end

  # Regression (row 110054): a head with a binary pattern must be left untouched.
  # Splitting it underscored the segment type specifiers (`utf8`/`binary`) into
  # invalid `_utf8`/`_binary`, producing non-compiling code that was reverted.
  test "does not touch a function head with a binary/bitstring pattern" do
    code = """
    defmodule M do
      defp collect(<<c1::utf8, rest1::binary>>, <<c2::utf8, rest2::binary>>, acc) do
        if c1 == c2 do
          collect(rest1, rest2, acc)
        else
          collect(rest1, rest2, [{c1, c2} | acc])
        end
      end
    end
    """

    confirm_fix(fix(PreferGuardOverIf, code), code)
  end
end
