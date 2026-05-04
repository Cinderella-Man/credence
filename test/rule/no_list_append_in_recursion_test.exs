defmodule Credence.Rule.NoListAppendInRecursionTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoListAppendInRecursion.check(ast, [])
  end

  defp fix(code) do
    Credence.Rule.NoListAppendInRecursion.fix(code, [])
  end

  describe "NoListAppendInRecursion check" do
    # --- POSITIVE CASES ---

    test "flags acc ++ [expr] directly in recursive call" do
      code = """
      defmodule Bad do
        def build([h | t], result) do
          build(t, result ++ [h * 2])
        end

        def build([], result), do: result
      end
      """

      issues = check(code)
      assert length(issues) == 1
      issue = hd(issues)
      assert issue.rule == :no_list_append_in_recursion
      assert issue.message =~ "++"
      assert issue.meta.line != nil
    end

    test "flags guarded recursive clause with direct append" do
      code = """
      defmodule Bad do
        defp helper([h | t], acc) when is_integer(h) do
          helper(t, acc ++ [h])
        end

        defp helper([], acc), do: acc
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_append_in_recursion
    end

    test "flags public recursive function" do
      code = """
      defmodule Bad do
        def collect([h | t], acc) do
          collect(t, acc ++ [String.upcase(h)])
        end

        def collect([], acc), do: acc
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    # --- NEGATIVE CASES ---

    test "does not flag non-recursive function" do
      code = """
      defmodule Safe do
        def prepare(list) do
          prefix = [0]
          prefix ++ list
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when ++ is indirect (assigned to variable)" do
      code = """
      defmodule Indirect do
        defp slide([next | rest], window, current, max) do
          new_window = window ++ [next]
          slide(rest, new_window, current, max)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag idiomatic prepend" do
      code = """
      defmodule Good do
        def build([h | t], acc), do: build(t, [h | acc])
        def build([], acc), do: Enum.reverse(acc)
      end
      """

      assert check(code) == []
    end

    test "does not flag ++ in Enum.reduce" do
      code = """
      defmodule NotRecursion do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            acc ++ [item]
          end)
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "NoListAppendInRecursion fix" do
    test "fixes simple two-clause recursive function" do
      code = """
      defmodule Example do
        def build([h | t], result) do
          build(t, result ++ [h * 2])
        end

        def build([], result), do: result
      end
      """

      fixed = fix(code)
      refute fixed =~ "++"
      assert fixed =~ "[h * 2 | result]" or fixed =~ "h * 2 | result"
      assert fixed =~ "Enum.reverse"
    end

    test "fixes guarded recursive clause" do
      code = """
      defmodule Example do
        defp helper([h | t], acc) when is_integer(h) do
          helper(t, acc ++ [h])
        end

        defp helper([], acc), do: acc
      end
      """

      fixed = fix(code)
      refute fixed =~ "++"
      assert fixed =~ "Enum.reverse"
    end

    test "fixes multi-expression recursive body" do
      code = """
      defmodule Example do
        def process([h | t], acc) do
          val = h * 2
          process(t, acc ++ [val])
        end

        def process([], acc), do: acc
      end
      """

      fixed = fix(code)
      refute fixed =~ "++"
      assert fixed =~ "val = h * 2"
      assert fixed =~ "Enum.reverse"
    end

    test "does not fix when no base case exists" do
      code = """
      defmodule Example do
        defp helper([h | t], acc) do
          helper(t, acc ++ [h])
        end
      end
      """

      fixed = fix(code)
      # No base case to add reverse to — cannot fix safely
      assert fixed =~ "++"
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

      fixed = fix(code)
      # Base case wraps result in tuple — cannot fix
      assert fixed =~ "++"
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

      fixed = fix(code)
      assert fixed =~ "++"
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

      fixed = fix(code)
      {:ok, ast} = Code.string_to_quoted(fixed)
      issues = Credence.Rule.NoListAppendInRecursion.check(ast, [])
      assert issues == []
    end
  end
end
