defmodule Credence.Pattern.NoSortThenAtCheckTest do
  use ExUnit.Case

  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoSortThenAt.check(ast, [])
  end

  describe "flags literal 0 and -1 indexes" do
    test "flags Enum.sort |> Enum.at(0)" do
      code = """
      defmodule M do
        def smallest(nums), do: Enum.sort(nums) |> Enum.at(0)
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end

    test "flags Enum.sort |> Enum.at(-1)" do
      code = """
      defmodule M do
        def largest(nums), do: Enum.sort(nums) |> Enum.at(-1)
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end

    test "flags Enum.sort(:desc) |> Enum.at(0)" do
      code = """
      defmodule M do
        def largest(nums), do: Enum.sort(nums, :desc) |> Enum.at(0)
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end

    test "flags nested Enum.at(Enum.sort(...), 0)" do
      code = """
      defmodule M do
        def smallest(nums), do: Enum.at(Enum.sort(nums), 0)
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end

    test "flags nested Enum.at(Enum.sort(...), -1)" do
      code = """
      defmodule M do
        def largest(nums), do: Enum.at(Enum.sort(nums), -1)
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end
  end

  describe "does NOT flag variable indexes" do
    test "does not flag Enum.sort |> Enum.at(k - 1)" do
      code = """
      defmodule M do
        def kth(nums, k), do: Enum.sort(nums, :desc) |> Enum.at(k - 1)
      end
      """

      assert check(code) == []
    end

    test "does not flag nested Enum.at(Enum.sort(...), div(n, 2))" do
      code = """
      defmodule M do
        def median(nums), do: Enum.at(Enum.sort(nums), div(length(nums), 2))
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.sort |> Enum.at(mid)" do
      code = """
      defmodule M do
        def middle(nums) do
          mid = div(length(nums), 2)
          Enum.sort(nums) |> Enum.at(mid)
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "does NOT flag other literal indexes (no stdlib replacement)" do
    test "does not flag Enum.sort |> Enum.at(1)" do
      code = """
      defmodule M do
        def second_smallest(nums), do: Enum.sort(nums) |> Enum.at(1)
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.sort |> Enum.at(3)" do
      code = """
      defmodule M do
        def fourth(nums), do: Enum.sort(nums) |> Enum.at(3)
      end
      """

      assert check(code) == []
    end

    test "does not flag nested Enum.at(Enum.sort(...), 2)" do
      code = """
      defmodule M do
        def third(nums), do: Enum.at(Enum.sort(nums), 2)
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.sort |> Enum.at(-2)" do
      code = """
      defmodule M do
        def second_largest(nums), do: Enum.sort(nums) |> Enum.at(-2)
      end
      """

      assert check(code) == []
    end
  end

  describe "does NOT flag unrelated patterns" do
    test "does not flag plain Enum.at" do
      code = """
      defmodule M do
        def get(list, i), do: Enum.at(list, i)
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.sort |> Enum.take" do
      code = """
      defmodule M do
        def top3(nums), do: Enum.sort(nums, :desc) |> Enum.take(3)
      end
      """

      assert check(code) == []
    end
  end
end
