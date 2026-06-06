defmodule Credence.Pattern.NoListAppendInRecursionCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoListAppendInRecursion

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoListAppendInRecursion.check(ast, [])
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
end
