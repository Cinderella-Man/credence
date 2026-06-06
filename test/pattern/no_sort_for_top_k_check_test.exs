defmodule Credence.Pattern.NoSortForTopKCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoSortForTopK

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoSortForTopK.check(ast, [])
  end

  describe "check — positive cases" do
    test "flags sort |> take(1)" do
      code = """
      defmodule Bad do
        def f(list), do: Enum.sort(list) |> Enum.take(1)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_sort_for_top_k
      assert issue.message =~ "Enum.min"
    end

    test "flags sort |> hd()" do
      code = """
      defmodule Bad do
        def f(list), do: Enum.sort(list) |> hd()
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.min"
    end

    test "flags sort |> Enum.at(0)" do
      code = """
      defmodule Bad do
        def f(list), do: Enum.sort(list) |> Enum.at(0)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.min"
    end

    test "flags sort |> reverse |> take(1)" do
      code = """
      defmodule Bad do
        def f(list), do: Enum.sort(list) |> Enum.reverse() |> Enum.take(1)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.max"
    end

    test "flags sort |> reverse |> hd()" do
      code = """
      defmodule Bad do
        def f(list), do: Enum.sort(list) |> Enum.reverse() |> hd()
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.max"
    end

    test "flags sort |> reverse |> Enum.at(0)" do
      code = """
      defmodule Bad do
        def f(list), do: Enum.sort(list) |> Enum.reverse() |> Enum.at(0)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.max"
    end

    test "flags inside anonymous function" do
      code = """
      Enum.map(list, fn x -> Enum.sort(x) |> Enum.take(1) end)
      """

      assert length(check(code)) == 1
    end

    test "flags with longer pipeline before sort (multiline)" do
      code = """
      defmodule Bad do
        def f(list) do
          Enum.sort(list)
          |> Enum.take(1)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags nested pipeline in tuple" do
      code = """
      Enum.map(list, &{&1, Enum.sort(&1) |> Enum.take(1)})
      """

      assert length(check(code)) == 1
    end
  end

  describe "check — negative cases" do
    test "does not flag sort |> take(k>1)" do
      code = """
      defmodule Good do
        def f(list), do: Enum.sort(list) |> Enum.take(2)
      end
      """

      assert check(code) == []
    end

    test "does not flag sort |> at(1)" do
      code = """
      defmodule Good do
        def f(list), do: Enum.sort(list) |> Enum.at(1)
      end
      """

      assert check(code) == []
    end

    test "does not flag sort |> take(1) followed by more steps" do
      code = """
      Enum.sort(list) |> Enum.take(1) |> length()
      """

      assert check(code) == []
    end

    test "does not flag unrelated pipelines" do
      code = """
      defmodule Good do
        def f(list), do: list |> Enum.map(&(&1 * 2)) |> Enum.take(1)
      end
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

    test "does not flag graphemes stored then counted" do
      code = """
      defmodule Good do
        def f(list) do
          sorted = Enum.sort(list)
          hd(sorted)
        end
      end
      """

      assert check(code) == []
    end
  end
end
