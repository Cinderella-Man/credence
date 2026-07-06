defmodule Credence.Pattern.PreferHeadPatternOverTailDestructureFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferHeadPatternOverTailDestructure

  describe "fix — rewrites the anti-pattern" do
    test "combines cons head and destructured tail into single pattern" do
      input = """
      defmodule Solution do
        def check([current_row | remaining_rows]) do
          [next_row | _] = remaining_rows
          tl(next_row)
          {current_row, next_row}
        end
      end
      """

      expected = """
      defmodule Solution do
        def check([current_row, next_row | _rest]) do
          tl(next_row)
          {current_row, next_row}
        end
      end
      """

      confirm_fix(fix(PreferHeadPatternOverTailDestructure, input), expected)
    end

    test "rewrites when binding is not the first statement" do
      input = """
      defmodule Solution do
        def check([a | b]) do
          x = a + 1
          [c | _] = b
          {x, c}
        end
      end
      """

      expected = """
      defmodule Solution do
        def check([a, c | _rest]) do
          x = a + 1
          {x, c}
        end
      end
      """

      confirm_fix(fix(PreferHeadPatternOverTailDestructure, input), expected)
    end

    test "preserves guard" do
      input = """
      defmodule Solution do
        def check([a | b]) when is_list(a) do
          [c | _] = b
          {a, c}
        end
      end
      """

      expected = """
      defmodule Solution do
        def check([a, c | _rest]) when is_list(a) do
          {a, c}
        end
      end
      """

      confirm_fix(fix(PreferHeadPatternOverTailDestructure, input), expected)
    end

    test "rewrites defp" do
      input = """
      defmodule Solution do
        defp process([head | tail]) do
          [first | _] = tail
          {head, first}
        end
      end
      """

      expected = """
      defmodule Solution do
        defp process([head, first | _rest]) do
          {head, first}
        end
      end
      """

      confirm_fix(fix(PreferHeadPatternOverTailDestructure, input), expected)
    end
  end

  describe "fix — leaves non-core shapes untouched" do
    test "no-op for already combined pattern" do
      code = """
      defmodule Solution do
        def check([current_row, next_row | _rest]) do
          tl(next_row)
          {current_row, next_row}
        end
      end
      """

      confirm_fix(fix(PreferHeadPatternOverTailDestructure, code), code)
    end

    test "no-op when tail is used elsewhere" do
      code = """
      defmodule Solution do
        def check([a | b]) do
          [c | _] = b
          {a, c, length(b)}
        end
      end
      """

      confirm_fix(fix(PreferHeadPatternOverTailDestructure, code), code)
    end

    test "no-op when inner tail is named" do
      code = """
      defmodule Solution do
        def check([a | b]) do
          [c | d] = b
          {a, c, d}
        end
      end
      """

      confirm_fix(fix(PreferHeadPatternOverTailDestructure, code), code)
    end

    test "no-op when binding is last statement" do
      code = """
      defmodule Solution do
        def check([a | b]) do
          {a, b}
          [c | _] = b
        end
      end
      """

      confirm_fix(fix(PreferHeadPatternOverTailDestructure, code), code)
    end
  end
end
