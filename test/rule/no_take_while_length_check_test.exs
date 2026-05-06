defmodule Credence.Pattern.NoTakeWhileLengthCheckTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoTakeWhileLengthCheck.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoTakeWhileLengthCheck.fix(code, [])
  end

  defp check_fix(code) do
    fixed = fix(code)
    {:ok, ast} = Code.string_to_quoted(fixed)
    issues = Credence.Pattern.NoTakeWhileLengthCheck.check(ast, [])
    {fixed, issues}
  end

  describe "NoTakeWhileLengthCheck detection" do
    test "detects Enum.take_while |> length() in pipeline" do
      code = """
      defmodule Bad do
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

      [issue] = check(code)
      assert issue.rule == :no_take_while_length_check
      assert issue.message =~ "Enum.all?"
    end

    test "detects Enum.take_while |> Enum.count() in pipeline" do
      code = """
      defmodule Bad do
        def count_matching(list) do
          list
          |> Enum.take_while(&(&1 > 0))
          |> Enum.count()
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.take_while"
    end

    test "detects two-step pipeline: Enum.take_while(enum, fn) |> length()" do
      code = """
      defmodule Bad do
        def check(items) do
          Enum.take_while(items, &is_integer/1) |> length()
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_take_while_length_check
    end

    test "detects direct call: length(Enum.take_while(...))" do
      code = """
      defmodule Bad do
        def count_valid(items) do
          length(Enum.take_while(items, &(&1 != nil)))
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_take_while_length_check
    end

    test "detects direct call: Enum.count(Enum.take_while(...))" do
      code = """
      defmodule Bad do
        def count_valid(items) do
          Enum.count(Enum.take_while(items, fn x -> x > 0 end))
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_take_while_length_check
    end

    test "detects in a comparison expression" do
      code = """
      defmodule Bad do
        def all_positive?(list) do
          Enum.take_while(list, &(&1 > 0)) |> length() == length(list)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.all?"
    end

    # ---- Negative cases ----

    test "does not flag Enum.take_while without length" do
      code = """
      defmodule Good do
        def leading_positives(list) do
          Enum.take_while(list, &(&1 > 0))
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.take_while piped into other functions" do
      code = """
      defmodule Good do
        def process(list) do
          list
          |> Enum.take_while(&(&1 > 0))
          |> Enum.map(&(&1 * 2))
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag length on non-take_while result" do
      code = """
      defmodule Good do
        def count(list) do
          list |> Enum.filter(&(&1 > 0)) |> length()
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.all? (correct pattern)" do
      code = """
      defmodule Good do
        def all_positive?(list) do
          Enum.all?(list, &(&1 > 0))
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.reduce_while (correct pattern)" do
      code = """
      defmodule Good do
        def count_leading(list) do
          Enum.reduce_while(list, 0, fn x, count ->
            if x > 0, do: {:cont, count + 1}, else: {:halt, count}
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag standalone length call" do
      code = """
      defmodule Good do
        def size(list), do: length(list)
      end
      """

      assert check(code) == []
    end
  end

  describe "NoTakeWhileLengthCheck fix" do
    test "fixes pipeline with capture predicate" do
      code = """
      defmodule Fixed do
        def check(items) do
          Enum.take_while(items, &is_integer/1) |> length()
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "Enum.reduce_while"
      assert fixed =~ "fn elem, acc ->"
      assert fixed =~ "&is_integer/1.(elem)"
      refute fixed =~ "take_while"

      {_, issues} = check_fix(code)
      assert issues == []
    end

    test "fixes pipeline with capture syntax predicate" do
      code = """
      defmodule Fixed do
        def count_matching(list) do
          list
          |> Enum.take_while(&(&1 > 0))
          |> Enum.count()
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "Enum.reduce_while"
      assert fixed =~ "fn elem, acc ->"
      refute fixed =~ "take_while"

      {_, issues} = check_fix(code)
      assert issues == []
    end

    test "fixes direct call: length(Enum.take_while(...))" do
      code = """
      defmodule Fixed do
        def count_valid(items) do
          length(Enum.take_while(items, &(&1 != nil)))
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "Enum.reduce_while(items, 0,"
      assert fixed =~ "fn elem, acc ->"
      refute fixed =~ "length("
      refute fixed =~ "take_while"

      {_, issues} = check_fix(code)
      assert issues == []
    end

    test "fixes direct call: Enum.count(Enum.take_while(...))" do
      code = """
      defmodule Fixed do
        def count_valid(items) do
          Enum.count(Enum.take_while(items, fn x -> x > 0 end))
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "Enum.reduce_while(items, 0,"
      assert fixed =~ "fn elem, acc ->"
      refute fixed =~ "Enum.count("
      refute fixed =~ "take_while"

      {_, issues} = check_fix(code)
      assert issues == []
    end

    test "fixes multiline fn predicate in pipeline" do
      code = """
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

      fixed = fix(code)
      assert fixed =~ "Enum.reduce_while"
      assert fixed =~ "fn elem, acc ->"
      assert fixed =~ ".(elem)"
      refute fixed =~ "take_while"

      {_, issues} = check_fix(code)
      assert issues == []
    end

    test "fixes comparison expression" do
      code = """
      defmodule Fixed do
        def all_positive?(list) do
          Enum.take_while(list, &(&1 > 0)) |> length() == length(list)
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "Enum.reduce_while(list, 0,"
      assert fixed =~ "== length(list)"
      refute fixed =~ "take_while"

      {_, issues} = check_fix(code)
      assert issues == []
    end

    test "fixes longer pipeline with take_while at end" do
      code = """
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

      fixed = fix(code)
      assert fixed =~ "Enum.reduce_while"
      assert fixed =~ "String.graphemes()"
      refute fixed =~ "take_while"

      {_, issues} = check_fix(code)
      assert issues == []
    end

    test "fixes multiple occurrences in same file" do
      code = """
      defmodule Fixed do
        def count_a(items) do
          Enum.take_while(items, &is_integer/1) |> length()
        end
        def count_b(items) do
          Enum.count(Enum.take_while(items, &is_binary/1))
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "Enum.reduce_while"
      refute fixed =~ "take_while"

      {_, issues} = check_fix(code)
      assert issues == []
    end

    test "fix does not modify non-flagged code" do
      code = """
      defmodule Good do
        def size(list), do: length(list)

        def all?(list), do: Enum.all?(list, &(&1 > 0))
      end
      """

      fixed = fix(code)
      assert fixed == code
    end

    test "fix preserves unrelated code in same module" do
      code = """
      defmodule Mixed do
        def count_leading(items) do
          Enum.take_while(items, &is_integer/1) |> length()
        end

        def other_func(list) do
          Enum.map(list, &(&1 * 2))
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "def other_func(list)"
      assert fixed =~ "Enum.map(list, &(&1 * 2))"
      refute fixed =~ "take_while"
    end
  end
end
