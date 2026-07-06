defmodule Credence.Pattern.PreferHeadPatternOverTailDestructureCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferHeadPatternOverTailDestructure

  describe "check — flags the anti-pattern" do
    test "flags when cons tail is immediately destructured" do
      code = """
      defmodule Solution do
        def check([current_row | remaining_rows]) do
          [next_row | _] = remaining_rows
          tl(next_row)
          {current_row, next_row}
        end
      end
      """

      issues = check(PreferHeadPatternOverTailDestructure, code)
      assert length(issues) == 1
      assert hd(issues).rule == :prefer_head_pattern_over_tail_destructure
    end

    test "flags when binding is not the first statement" do
      code = """
      defmodule Solution do
        def check([a | b]) do
          x = a + 1
          [c | _] = b
          {x, c}
        end
      end
      """

      assert length(check(PreferHeadPatternOverTailDestructure, code)) == 1
    end

    test "flags defp too" do
      code = """
      defmodule Solution do
        defp process([head | tail]) do
          [first | _] = tail
          {head, first}
        end
      end
      """

      assert length(check(PreferHeadPatternOverTailDestructure, code)) == 1
    end

    test "flags the LAST clause when a preceding base clause catches the short list" do
      # Clause 1 (`[_ | []]`) already catches every one-element list, so narrowing
      # the last clause cannot change dispatch — safe, and it should fire.
      code = """
      defmodule Solution do
        def check([_ | []]), do: :one

        def check([current | remaining]) do
          [next | _] = remaining
          _ = next
          {current, next}
        end
      end
      """

      assert length(check(PreferHeadPatternOverTailDestructure, code)) == 1
    end

    test "flags with guard that does not reference tail var" do
      code = """
      defmodule Solution do
        def check([a | b]) when is_list(a) do
          [c | _] = b
          {a, c}
        end
      end
      """

      assert length(check(PreferHeadPatternOverTailDestructure, code)) == 1
    end
  end

  describe "check — deliberately not flagged (locks the safe-core choice)" do
    test "no issue for already combined pattern" do
      code = """
      defmodule Solution do
        def check([current_row, next_row | _rest]) do
          tl(next_row)
          {current_row, next_row}
        end
      end
      """

      assert check(PreferHeadPatternOverTailDestructure, code) == []
    end

    test "no issue when tail is used elsewhere in body" do
      code = """
      defmodule Solution do
        def check([a | b]) do
          [c | _] = b
          {a, c, length(b)}
        end
      end
      """

      assert check(PreferHeadPatternOverTailDestructure, code) == []
    end

    test "no issue when no cons pattern in head" do
      code = """
      defmodule Solution do
        def check(list) do
          [a | _] = list
          a
        end
      end
      """

      assert check(PreferHeadPatternOverTailDestructure, code) == []
    end

    test "no issue when no destructuring of tail" do
      code = """
      defmodule Solution do
        def check([a | b]) do
          {a, b}
        end
      end
      """

      assert check(PreferHeadPatternOverTailDestructure, code) == []
    end

    test "no issue when tail is used in guard" do
      code = """
      defmodule Solution do
        def check([a | b]) when length(b) > 0 do
          [c | _] = b
          {a, c}
        end
      end
      """

      assert check(PreferHeadPatternOverTailDestructure, code) == []
    end

    test "no issue when inner tail is a named variable" do
      code = """
      defmodule Solution do
        def check([a | b]) do
          [c | d] = b
          {a, c, d}
        end
      end
      """

      assert check(PreferHeadPatternOverTailDestructure, code) == []
    end

    test "no issue when binding is the last statement" do
      code = """
      defmodule Solution do
        def check([a | b]) do
          {a, b}
          [c | _] = b
        end
      end
      """

      assert check(PreferHeadPatternOverTailDestructure, code) == []
    end

    test "no issue when tail var is used in another parameter" do
      code = """
      defmodule Solution do
        def check([a | b], x) do
          [c | _] = b
          {a, c, x, b}
        end
      end
      """

      assert check(PreferHeadPatternOverTailDestructure, code) == []
    end

    test "no issue when function head tail is underscore" do
      code = """
      defmodule Solution do
        def check([a | _]) do
          a
        end
      end
      """

      assert check(PreferHeadPatternOverTailDestructure, code) == []
    end

    test "no issue when a LATER clause could catch the narrowed-away single-element list (dispatch safety)" do
      # Old head `[a | b]` accepts `[x]` then MatchErrors on `[c | _] = []`.
      # Narrowing to `[a, c | _]` would make `[x]` fall through to `check([_x])`
      # and return :single instead of raising — a dispatch change. Must NOT fire.
      code = """
      defmodule Solution do
        def check([a | b]) do
          [c | _] = b
          _ = c
          {a, c}
        end

        def check([_x]), do: :single
      end
      """

      assert check(PreferHeadPatternOverTailDestructure, code) == []
    end
  end
end
