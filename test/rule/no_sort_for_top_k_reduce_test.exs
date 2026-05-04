defmodule Credence.Rule.NoSortForTopKReduceTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoSortForTopKReduce.check(ast, [])
  end

  # ── positive cases ───────────────────────────────────────────────

  describe "positive cases" do
    test "flags sort |> take(2)" do
      code = """
      defmodule Bad do
        def f(list), do: Enum.sort(list) |> Enum.take(2)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_sort_for_top_k_reduce
      assert issue.message =~ "top 2"
    end

    test "flags sort |> take(3)" do
      code = """
      defmodule Bad do
        def f(list), do: Enum.sort(list) |> Enum.take(3)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "top 3"
    end

    test "flags sort |> Enum.at(1)" do
      code = """
      defmodule Bad do
        def f(list), do: Enum.sort(list) |> Enum.at(1)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.reduce"
      assert issue.message =~ "smallest"
    end

    test "flags sort |> reverse |> take(2)" do
      code = """
      defmodule Bad do
        def f(list), do: Enum.sort(list) |> Enum.reverse() |> Enum.take(2)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "top 2"
      assert issue.message =~ "largest"
    end

    test "flags sort |> reverse |> Enum.at(1)" do
      code = """
      defmodule Bad do
        def f(list), do: Enum.sort(list) |> Enum.reverse() |> Enum.at(1)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "largest"
    end

    test "flags inside Enum.map" do
      code = """
      Enum.map(list, fn x -> Enum.sort(x) |> Enum.take(2) end)
      """

      assert length(check(code)) == 1
    end

    test "flags with longer pipeline before sort" do
      code = """
      defmodule Bad do
        def f(list) do
          Enum.sort(list)
          |> Enum.take(5)
        end
      end
      """

      assert length(check(code)) == 1
    end
  end

  # ── negative cases ───────────────────────────────────────────────

  describe "negative cases" do
    test "does not flag sort |> take(1)" do
      code = """
      defmodule Good do
        def f(list), do: Enum.sort(list) |> Enum.take(1)
      end
      """

      assert check(code) == []
    end

    test "does not flag sort |> hd()" do
      code = """
      defmodule Good do
        def f(list), do: Enum.sort(list) |> hd()
      end
      """

      assert check(code) == []
    end

    test "does not flag sort |> at(0)" do
      code = """
      defmodule Good do
        def f(list), do: Enum.sort(list) |> Enum.at(0)
      end
      """

      assert check(code) == []
    end

    test "does not flag unrelated pipelines" do
      code = """
      defmodule Good do
        def f(list), do: list |> Enum.map(&(&1 * 2)) |> Enum.take(2)
      end
      """

      assert check(code) == []
    end

    test "does not flag sort |> take(2) followed by more steps" do
      code = """
      Enum.sort(list) |> Enum.take(2) |> length()
      """

      assert check(code) == []
    end

    test "does not flag Enum.min directly" do
      code = """
      defmodule Good do
        def f(list), do: Enum.min(list)
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.sort |> Enum.reverse |> Enum.at(2)" do
      # at(2) is not in our pattern set
      code = """
      def f(list), do: Enum.sort(list) |> Enum.at(2)
      """

      assert check(code) == []
    end
  end
end
