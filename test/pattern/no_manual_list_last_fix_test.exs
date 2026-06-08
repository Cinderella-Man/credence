defmodule Credence.Pattern.NoManualListLastFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoManualListLast

  describe "fix" do
    test "replaces hand-rolled function with hd(Enum.reverse/1) delegation" do
      input = """
      defmodule Bad do
        defp get_last_element([val]), do: val
        defp get_last_element([_ | rest]), do: get_last_element(rest)
      end
      """

      expected = """
      defmodule Bad do
        defp get_last_element(list) do
          hd(Enum.reverse(list))
        end
      end
      """

      assert fix(NoManualListLast, input) == expected
    end

    test "replaces direct calls to the function" do
      input = """
      defmodule Bad do
        defp get_last_element([val]), do: val
        defp get_last_element([_ | rest]), do: get_last_element(rest)

        def run(list), do: get_last_element(list)
      end
      """

      expected = """
      defmodule Bad do
        defp get_last_element(list) do
          hd(Enum.reverse(list))
        end

        def run(list), do: hd(Enum.reverse(list))
      end
      """

      assert fix(NoManualListLast, input) == expected
    end

    test "replaces pipe calls" do
      input = """
      defmodule Bad do
        defp last([val]), do: val
        defp last([_ | rest]), do: last(rest)

        def run(list), do: list |> last()
      end
      """

      expected = """
      defmodule Bad do
        defp last(list) do
          hd(Enum.reverse(list))
        end

        def run(list), do: list |> Enum.reverse() |> hd()
      end
      """

      assert fix(NoManualListLast, input) == expected
    end

    test "does not modify code without the pattern" do
      code = """
      defmodule Good do
        def run(list), do: hd(Enum.reverse(list))
      end
      """

      assert fix(NoManualListLast, code) == code
    end

    test "handles clauses in reverse order" do
      input = """
      defmodule Bad do
        defp my_last([_ | rest]), do: my_last(rest)
        defp my_last([val]), do: val
      end
      """

      expected = """
      defmodule Bad do
        defp my_last(list) do
          hd(Enum.reverse(list))
        end
      end
      """

      assert fix(NoManualListLast, input) == expected
    end

    test "handles def (public) functions" do
      input = """
      defmodule Bad do
        def final([el]), do: el
        def final([_ | rest]), do: final(rest)
      end
      """

      expected = """
      defmodule Bad do
        def final(list) do
          hd(Enum.reverse(list))
        end
      end
      """

      assert fix(NoManualListLast, input) == expected
    end

    test "handles function called inside nested expression" do
      input = """
      defmodule Bad do
        defp last([val]), do: val
        defp last([_ | rest]), do: last(rest)

        def run(list), do: {last(list), :ok}
      end
      """

      expected = """
      defmodule Bad do
        defp last(list) do
          hd(Enum.reverse(list))
        end

        def run(list), do: {hd(Enum.reverse(list)), :ok}
      end
      """

      assert fix(NoManualListLast, input) == expected
    end

    test "handles function called inside fn" do
      input = """
      defmodule Bad do
        defp last([val]), do: val
        defp last([_ | rest]), do: last(rest)

        def run(lists), do: Enum.map(lists, fn x -> last(x) end)
      end
      """

      expected = """
      defmodule Bad do
        defp last(list) do
          hd(Enum.reverse(list))
        end

        def run(lists), do: Enum.map(lists, fn x -> hd(Enum.reverse(x)) end)
      end
      """

      assert fix(NoManualListLast, input) == expected
    end

    test "handles function called inside case" do
      input = """
      defmodule Bad do
        defp last([val]), do: val
        defp last([_ | rest]), do: last(rest)

        def run(list) do
          case :ok do
            :ok -> last(list)
            _ -> nil
          end
        end
      end
      """

      expected = """
      defmodule Bad do
        defp last(list) do
          hd(Enum.reverse(list))
        end

        def run(list) do
          case :ok do
            :ok -> hd(Enum.reverse(list))
            _ -> nil
          end
        end
      end
      """

      assert fix(NoManualListLast, input) == expected
    end

    test "handles multiple matching functions" do
      input = """
      defmodule Bad do
        defp last_a([val]), do: val
        defp last_a([_ | rest]), do: last_a(rest)

        defp last_b([val]), do: val
        defp last_b([_ | rest]), do: last_b(rest)
      end
      """

      expected = """
      defmodule Bad do
        defp last_a(list) do
          hd(Enum.reverse(list))
        end

        defp last_b(list) do
          hd(Enum.reverse(list))
        end
      end
      """

      assert fix(NoManualListLast, input) == expected
    end

    test "preserves other functions in the module" do
      input = """
      defmodule Bad do
        defp last([val]), do: val
        defp last([_ | rest]), do: last(rest)

        def other(x), do: x + 1
      end
      """

      expected = """
      defmodule Bad do
        defp last(list) do
          hd(Enum.reverse(list))
        end

        def other(x), do: x + 1
      end
      """

      assert fix(NoManualListLast, input) == expected
    end

    test "returns original source when no matches found" do
      code = """
      defmodule Good do
        def run(list), do: hd(list)
      end
      """

      assert fix(NoManualListLast, code) == code
    end

    test "handles longer pipeline before the function call" do
      input = """
      defmodule Bad do
        defp last([val]), do: val
        defp last([_ | rest]), do: last(rest)

        def run(list), do:
          list
          |> Enum.map(&(&1))
          |> last()
      end
      """

      expected = """
      defmodule Bad do
        defp last(list) do
          hd(Enum.reverse(list))
        end

        def run(list),
          do:
            list
            |> Enum.map(& &1)
            |> Enum.reverse()
            |> hd()
      end
      """

      assert fix(NoManualListLast, input) == expected
    end

    test "handles function with non-adjacent clauses" do
      input = """
      defmodule Bad do
        defp last([val]), do: val
        def other(x), do: x + 1
        defp last([_ | rest]), do: last(rest)
      end
      """

      expected = """
      defmodule Bad do
        defp last(list) do
          hd(Enum.reverse(list))
        end

        def other(x), do: x + 1
      end
      """

      assert fix(NoManualListLast, input) == expected
    end

    test "handles function called in a tuple" do
      input = """
      defmodule Bad do
        defp last([val]), do: val
        defp last([_ | rest]), do: last(rest)

        def run(list), do: {last(list), last(list)}
      end
      """

      expected = """
      defmodule Bad do
        defp last(list) do
          hd(Enum.reverse(list))
        end

        def run(list), do: {hd(Enum.reverse(list)), hd(Enum.reverse(list))}
      end
      """

      assert fix(NoManualListLast, input) == expected
    end

    test "does not affect functions with similar but different patterns" do
      code = """
      defmodule Good do
        defp sum([val]), do: val
        defp sum([head | rest]), do: head + sum(rest)

        def run(list), do: sum(list)
      end
      """

      assert fix(NoManualListLast, code) == code
    end
  end
end
