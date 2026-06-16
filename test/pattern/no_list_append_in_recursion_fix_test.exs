defmodule Credence.Pattern.NoListAppendInRecursionFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoListAppendInRecursion

  describe "NoListAppendInRecursion fix" do
    test "fixes simple two-clause recursive function" do
      input = """
      defmodule Example do
        def build([h | t], result) do
          build(t, result ++ [h * 2])
        end

        def build([], result), do: result
      end
      """

      expected = """
      defmodule Example do
        def build([h | t], result) do
          build(t, [h * 2 | result])
        end

        def build([], result), do: Enum.reverse(result)
      end
      """

      confirm_fix(fix(NoListAppendInRecursion, input), expected)
    end

    test "fixes guarded recursive clause" do
      input = """
      defmodule Example do
        defp helper([h | t], acc) when is_integer(h) do
          helper(t, acc ++ [h])
        end

        defp helper([], acc), do: acc
      end
      """

      expected = """
      defmodule Example do
        defp helper([h | t], acc) when is_integer(h) do
          helper(t, [h | acc])
        end

        defp helper([], acc), do: Enum.reverse(acc)
      end
      """

      confirm_fix(fix(NoListAppendInRecursion, input), expected)
    end

    test "fixes multi-expression recursive body" do
      input = """
      defmodule Example do
        def process([h | t], acc) do
          val = h * 2
          process(t, acc ++ [val])
        end

        def process([], acc), do: acc
      end
      """

      expected = """
      defmodule Example do
        def process([h | t], acc) do
          val = h * 2
          process(t, [val | acc])
        end

        def process([], acc), do: Enum.reverse(acc)
      end
      """

      confirm_fix(fix(NoListAppendInRecursion, input), expected)
    end

    test "does not fix when no base case exists" do
      code = """
      defmodule Example do
        defp helper([h | t], acc) do
          helper(t, acc ++ [h])
        end
      end
      """

      # No base case to add reverse to — cannot fix safely.
      confirm_fix(fix(NoListAppendInRecursion, code), code)
    end

    test "does not fix when base case does not return accumulator directly" do
      code = """
      defmodule Example do
        def build([h | t], result) do
          build(t, result ++ [h])
        end

        def build([], result), do: {:ok, result}
      end
      """

      # Base case wraps result in tuple — cannot fix.
      confirm_fix(fix(NoListAppendInRecursion, code), code)
    end

    test "does not fix indirect append (assigned to variable)" do
      code = """
      defmodule Example do
        defp slide([next | rest], window, current, max) do
          new_window = window ++ [next]
          slide(rest, new_window, current, max)
        end

        defp slide([], window, _current, max), do: {window, max}
      end
      """

      confirm_fix(fix(NoListAppendInRecursion, code), code)
    end

    test "fixed code has no remaining issues" do
      code = """
      defmodule Example do
        def build([h | t], result) do
          build(t, result ++ [h * 2])
        end

        def build([], result), do: result
      end
      """

      assert check(NoListAppendInRecursion, fix(NoListAppendInRecursion, code)) == []
    end
  end
end
