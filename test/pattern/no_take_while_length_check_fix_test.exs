defmodule Credence.Pattern.NoTakeWhileLengthCheckFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoTakeWhileLengthCheck

  describe "NoTakeWhileLengthCheck fix" do
    test "fixes pipeline with capture predicate" do
      input = """
      defmodule Fixed do
        def check(items) do
          Enum.take_while(items, &is_integer/1) |> length()
        end
      end
      """

      expected = """
      defmodule Fixed do
        def check(items) do
          Enum.reduce_while(items, 0, fn elem, acc -> if (&is_integer/1).(elem), do: {:cont, acc + 1}, else: {:halt, acc} end)
        end
      end
      """

      assert fix(NoTakeWhileLengthCheck, input) == expected
    end

    test "fixes pipeline with capture syntax predicate" do
      input = """
      defmodule Fixed do
        def count_matching(list) do
          list
          |> Enum.take_while(&(&1 > 0))
          |> Enum.count()
        end
      end
      """

      expected = """
      defmodule Fixed do
        def count_matching(list) do
          list
          |> Enum.reduce_while(0, fn elem, acc -> if (&(&1 > 0)).(elem), do: {:cont, acc + 1}, else: {:halt, acc} end)
        end
      end
      """

      assert fix(NoTakeWhileLengthCheck, input) == expected
    end

    test "fixes direct call: length(Enum.take_while(...))" do
      input = """
      defmodule Fixed do
        def count_valid(items) do
          length(Enum.take_while(items, &(&1 != nil)))
        end
      end
      """

      expected = """
      defmodule Fixed do
        def count_valid(items) do
          Enum.reduce_while(items, 0, fn elem, acc -> if (&(&1 != nil)).(elem), do: {:cont, acc + 1}, else: {:halt, acc} end)
        end
      end
      """

      assert fix(NoTakeWhileLengthCheck, input) == expected
    end

    test "fixes direct call: Enum.count(Enum.take_while(...))" do
      input = """
      defmodule Fixed do
        def count_valid(items) do
          Enum.count(Enum.take_while(items, fn x -> x > 0 end))
        end
      end
      """

      expected = """
      defmodule Fixed do
        def count_valid(items) do
          Enum.reduce_while(items, 0, fn elem, acc -> if (fn x -> x > 0 end).(elem), do: {:cont, acc + 1}, else: {:halt, acc} end)
        end
      end
      """

      assert fix(NoTakeWhileLengthCheck, input) == expected
    end

    test "fixes multiline fn predicate in pipeline" do
      input = """
      defmodule Fixed do
        def palindrome?(graphemes, start, len) do
          half = div(len, 2)
          0..(half - 1)
          |> Enum.take_while(fn i ->
            Enum.at(graphemes, start + i) == Enum.at(graphemes, start + len - 1 - i)
          end)
          |> length() == half
        end
      end
      """

      expected = """
      defmodule Fixed do
        def palindrome?(graphemes, start, len) do
          half = div(len, 2)
          0..(half - 1)
          |> Enum.reduce_while(0, fn elem, acc -> if (fn i ->
            Enum.at(graphemes, start + i) == Enum.at(graphemes, start + len - 1 - i)
          end).(elem), do: {:cont, acc + 1}, else: {:halt, acc} end) == half
        end
      end
      """

      assert fix(NoTakeWhileLengthCheck, input) == expected
    end

    test "fixes comparison expression" do
      input = """
      defmodule Fixed do
        def all_positive?(list) do
          Enum.take_while(list, &(&1 > 0)) |> length() == length(list)
        end
      end
      """

      expected = """
      defmodule Fixed do
        def all_positive?(list) do
          Enum.reduce_while(list, 0, fn elem, acc -> if (&(&1 > 0)).(elem), do: {:cont, acc + 1}, else: {:halt, acc} end) == length(list)
        end
      end
      """

      assert fix(NoTakeWhileLengthCheck, input) == expected
    end

    test "fixes longer pipeline with take_while at end" do
      input = """
      defmodule Fixed do
        def check(str) do
          str
          |> String.trim()
          |> String.graphemes()
          |> Enum.take_while(&(&1 != " "))
          |> length()
        end
      end
      """

      expected = """
      defmodule Fixed do
        def check(str) do
          str
          |> String.trim()
          |> String.graphemes()
          |> Enum.reduce_while(0, fn elem, acc -> if (&(&1 != " ")).(elem), do: {:cont, acc + 1}, else: {:halt, acc} end)
        end
      end
      """

      assert fix(NoTakeWhileLengthCheck, input) == expected
    end

    test "fixes multiple occurrences in same file" do
      input = """
      defmodule Fixed do
        def count_a(items) do
          Enum.take_while(items, &is_integer/1) |> length()
        end
        def count_b(items) do
          Enum.count(Enum.take_while(items, &is_binary/1))
        end
      end
      """

      expected = """
      defmodule Fixed do
        def count_a(items) do
          Enum.reduce_while(items, 0, fn elem, acc -> if (&is_integer/1).(elem), do: {:cont, acc + 1}, else: {:halt, acc} end)
        end
        def count_b(items) do
          Enum.reduce_while(items, 0, fn elem, acc -> if (&is_binary/1).(elem), do: {:cont, acc + 1}, else: {:halt, acc} end)
        end
      end
      """

      assert fix(NoTakeWhileLengthCheck, input) == expected
    end

    test "fix does not modify non-flagged code" do
      code = """
      defmodule Good do
        def size(list), do: length(list)

        def all?(list), do: Enum.all?(list, &(&1 > 0))
      end
      """

      assert fix(NoTakeWhileLengthCheck, code) == code
    end

    test "fix preserves unrelated code in same module" do
      input = """
      defmodule Mixed do
        def count_leading(items) do
          Enum.take_while(items, &is_integer/1) |> length()
        end

        def other_func(list) do
          Enum.map(list, &(&1 * 2))
        end
      end
      """

      expected = """
      defmodule Mixed do
        def count_leading(items) do
          Enum.reduce_while(items, 0, fn elem, acc -> if (&is_integer/1).(elem), do: {:cont, acc + 1}, else: {:halt, acc} end)
        end

        def other_func(list) do
          Enum.map(list, &(&1 * 2))
        end
      end
      """

      assert fix(NoTakeWhileLengthCheck, input) == expected
    end
  end
end
