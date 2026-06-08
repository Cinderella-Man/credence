defmodule Credence.Pattern.NoSortForTopKCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoSortForTopK

  describe "check — positive cases (Enum.at(0) terminal only)" do
    test "flags sort |> Enum.at(0)" do
      code = """
      defmodule Bad do
        def f(list), do: Enum.sort(list) |> Enum.at(0)
      end
      """

      [issue] = check(NoSortForTopK, code)
      assert issue.rule == :no_sort_for_top_k
      assert issue.message =~ "Enum.min"
    end

    test "flags sort |> reverse |> Enum.at(0)" do
      code = """
      defmodule Bad do
        def f(list), do: Enum.sort(list) |> Enum.reverse() |> Enum.at(0)
      end
      """

      [issue] = check(NoSortForTopK, code)
      assert issue.message =~ "Enum.max"
    end

    test "flags inside anonymous function" do
      code = """
      Enum.map(list, fn x -> Enum.sort(x) |> Enum.at(0) end)
      """

      assert length(check(NoSortForTopK, code)) == 1
    end

    test "flags with longer pipeline before sort (multiline)" do
      code = """
      defmodule Bad do
        def f(list) do
          Enum.sort(list)
          |> Enum.at(0)
        end
      end
      """

      assert length(check(NoSortForTopK, code)) == 1
    end

    test "flags nested pipeline in tuple" do
      code = """
      Enum.map(list, &{&1, Enum.sort(&1) |> Enum.at(0)})
      """

      assert length(check(NoSortForTopK, code)) == 1
    end
  end

  describe "check — negative cases" do
    test "does not flag sort |> take(1) (returns a list, not the scalar min)" do
      code = """
      defmodule Good do
        def f(list), do: Enum.sort(list) |> Enum.take(1)
      end
      """

      assert check(NoSortForTopK, code) == []
    end

    test "does not flag sort |> hd() (hd([]) raises ArgumentError, not Enum.EmptyError)" do
      code = """
      defmodule Good do
        def f(list), do: Enum.sort(list) |> hd()
      end
      """

      assert check(NoSortForTopK, code) == []
    end

    test "does not flag sort |> reverse |> take(1)" do
      code = """
      defmodule Good do
        def f(list), do: Enum.sort(list) |> Enum.reverse() |> Enum.take(1)
      end
      """

      assert check(NoSortForTopK, code) == []
    end

    test "does not flag sort |> reverse |> hd()" do
      code = """
      defmodule Good do
        def f(list), do: Enum.sort(list) |> Enum.reverse() |> hd()
      end
      """

      assert check(NoSortForTopK, code) == []
    end

    test "does not flag sort |> take(k>1)" do
      code = """
      defmodule Good do
        def f(list), do: Enum.sort(list) |> Enum.take(2)
      end
      """

      assert check(NoSortForTopK, code) == []
    end

    test "does not flag sort |> at(1)" do
      code = """
      defmodule Good do
        def f(list), do: Enum.sort(list) |> Enum.at(1)
      end
      """

      assert check(NoSortForTopK, code) == []
    end

    test "does not flag sort |> at(0) followed by more steps" do
      code = """
      Enum.sort(list) |> Enum.at(0) |> to_string()
      """

      assert check(NoSortForTopK, code) == []
    end

    test "does not flag unrelated pipelines" do
      code = """
      defmodule Good do
        def f(list), do: list |> Enum.map(&(&1 * 2)) |> Enum.at(0)
      end
      """

      assert check(NoSortForTopK, code) == []
    end

    test "does not flag Enum.min directly" do
      code = """
      defmodule Good do
        def f(list), do: Enum.min(list)
      end
      """

      assert check(NoSortForTopK, code) == []
    end

    test "does not flag sort stored then accessed separately" do
      code = """
      defmodule Good do
        def f(list) do
          sorted = Enum.sort(list)
          hd(sorted)
        end
      end
      """

      assert check(NoSortForTopK, code) == []
    end
  end
end
