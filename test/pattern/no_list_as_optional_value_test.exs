defmodule Credence.Pattern.NoListAsOptionalValueTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoListAsOptionalValue

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoListAsOptionalValue.check(ast, [])
  end

  describe "check/2" do
    test "detects list as optional container with List.last unwrap" do
      code = """
      defmodule Example do
        def run(list) do
          list
          |> Enum.sort()
          |> adjust(0, [])
        end

        defp adjust([], acc, _prev), do: acc
        defp adjust([x | rest], acc, []) do
          adjust(rest, acc, [x])
        end

        defp adjust([x | rest], acc, wrapped) do
          val = List.last(wrapped)
          adjust(rest, acc + val, [x + 1])
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_list_as_optional_value
      assert issue.message =~ "List.last"
    end

    test "detects the generated min_increments pattern" do
      code = """
      defmodule Solution do
        def min_increments(numbers) do
          numbers
          |> Enum.sort()
          |> adjust_duplicates(0, [])
        end

        defp adjust_duplicates([], total_increments, _previous_numbers) do
          total_increments
        end

        defp adjust_duplicates([current | remaining], total_increments, []) do
          adjust_duplicates(remaining, total_increments, [current])
        end

        defp adjust_duplicates([current | remaining], total_increments, previous_numbers) do
          previous = List.last(previous_numbers)
          new_previous = max(current, previous + 1)
          new_increments = total_increments + (new_previous - current)
          adjust_duplicates(remaining, new_increments, [new_previous])
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_as_optional_value
    end

    test "does not flag List.last on regular list" do
      code = """
      defmodule Example do
        def last(list), do: List.last(list)
      end
      """

      assert check(code) == []
    end

    test "does not flag when no empty list pattern in any clause" do
      code = """
      defmodule Example do
        defp process([x | rest], wrapped) do
          val = List.last(wrapped)
          process(rest, [val + x])
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when recursive call passes multi-element list" do
      code = """
      defmodule Example do
        defp process([], acc), do: acc
        defp process([x | rest], items) do
          last = List.last(items)
          process(rest, [x | items])
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when no recursive calls exist" do
      code = """
      defmodule Example do
        defp process([], acc), do: acc
        defp process([_x | _rest], wrapped) do
          List.last(wrapped)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag single-clause functions" do
      code = """
      defmodule Example do
        defp process(wrapped) do
          List.last(wrapped)
        end
      end
      """

      assert check(code) == []
    end
  end
end
