defmodule Credence.Pattern.NoSortThenReverseTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoSortThenReverse.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoSortThenReverse.fix(code, [])
  end

  # Collapse all whitespace so assertions aren't sensitive to formatter line breaks
  defp compact(str), do: String.replace(str, ~r/\s+/, " ")

  describe "check" do
    test "detects Enum.sort |> Enum.reverse pipeline" do
      code = """
      defmodule BadPipeline do
        def descending(nums) do
          nums |> Enum.sort() |> Enum.reverse()
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_sort_then_reverse
      assert issue.message =~ "Enum.sort(list, :desc)"
      assert issue.meta.line != nil
    end

    test "detects nested call Enum.reverse(Enum.sort(...))" do
      code = """
      defmodule BadNested do
        def descending(nums) do
          Enum.reverse(Enum.sort(nums))
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_sort_then_reverse
    end

    test "detects longer pipeline before sort" do
      code = """
      defmodule BadLongPipeline do
        def descending(nums) do
          nums
          |> Enum.filter(&(&1 > 0))
          |> Enum.sort()
          |> Enum.reverse()
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "detects inside Enum.map" do
      code = """
      defmodule BadInMap do
        def sort_all(lists) do
          Enum.map(lists, fn x -> Enum.sort(x) |> Enum.reverse() end)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "detects nested pipeline in tuple" do
      code = """
      defmodule BadTuple do
        def process(list) do
          Enum.map(list, &{&1, &1 |> Enum.sort() |> Enum.reverse()})
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "detects custom comparator pipeline" do
      code = """
      defmodule CustomSort do
        def process(list) do
          Enum.sort(list, &(&1.name <= &2.name)) |> Enum.reverse()
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "does not flag Enum.sort with :desc" do
      code = """
      defmodule GoodSort do
        def top_three(nums) do
          Enum.sort(nums, :desc) |> Enum.take(3)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.reverse without preceding sort" do
      code = """
      defmodule SafeReverse do
        def process(list) do
          Enum.reverse(list)
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    test "fixes simple pipeline" do
      input = """
      defmodule Example do
        def descending(nums) do
          nums |> Enum.sort() |> Enum.reverse()
        end
      end
      """

      result = fix(input)
      assert result =~ "Enum.sort(:desc)"
      refute result =~ "Enum.reverse"
    end

    test "fixes nested call" do
      input = """
      defmodule Example do
        def descending(nums) do
          Enum.reverse(Enum.sort(nums))
        end
      end
      """

      result = fix(input)
      assert compact(result) =~ "Enum.sort( nums, :desc )"
      refute result =~ "Enum.reverse"
    end

    test "fixes longer pipeline preserving prefix" do
      input = """
      defmodule Example do
        def descending(nums) do
          nums
          |> Enum.filter(&(&1 > 0))
          |> Enum.sort()
          |> Enum.reverse()
        end
      end
      """

      result = fix(input)
      assert result =~ "Enum.sort(:desc)"
      assert result =~ "Enum.filter"
      refute result =~ "Enum.reverse"
    end

    test "fixes inside Enum.map" do
      input = """
      defmodule Example do
        def sort_all(lists) do
          Enum.map(lists, fn x -> Enum.sort(x) |> Enum.reverse() end)
        end
      end
      """

      result = fix(input)
      assert compact(result) =~ "Enum.sort(x, :desc)"
      refute result =~ "Enum.reverse"
    end

    test "fixes Enum.sort(:asc) pipeline to :desc" do
      input = """
      defmodule Example do
        def descending(nums) do
          nums |> Enum.sort(:asc) |> Enum.reverse()
        end
      end
      """

      result = fix(input)
      assert result =~ "Enum.sort(:desc)"
      refute result =~ "Enum.reverse"
      refute result =~ ":asc"
    end

    test "fixes nested Enum.reverse(Enum.sort(x, :asc))" do
      input = """
      defmodule Example do
        def descending(nums) do
          Enum.reverse(Enum.sort(nums, :asc))
        end
      end
      """

      result = fix(input)
      assert compact(result) =~ "Enum.sort( nums, :desc )"
      refute result =~ "Enum.reverse"
    end

    test "fixes Enum.sort(:desc) |> Enum.reverse to ascending" do
      input = """
      defmodule Example do
        def ascending(nums) do
          nums |> Enum.sort(:desc) |> Enum.reverse()
        end
      end
      """

      result = fix(input)
      assert result =~ "Enum.sort"
      refute result =~ ":desc"
      refute result =~ "Enum.reverse"
    end

    test "fixes Enum.sort(x) |> Enum.reverse() direct-call-to-pipe" do
      input = """
      defmodule Example do
        def descending(nums) do
          Enum.sort(nums) |> Enum.reverse()
        end
      end
      """

      result = fix(input)
      assert compact(result) =~ "Enum.sort( nums, :desc )"
      refute result =~ "Enum.reverse"
    end

    test "fixes direct nested Enum.reverse(Enum.sort(x, :desc)) to ascending" do
      input = """
      defmodule Example do
        def ascending(nums) do
          Enum.reverse(Enum.sort(nums, :desc))
        end
      end
      """

      result = fix(input)
      assert compact(result) =~ "Enum.sort(nums)"
      refute result =~ ":desc"
      refute result =~ "Enum.reverse"
    end

    test "does not fix custom comparator pipeline" do
      input = """
      defmodule Example do
        def process(list) do
          Enum.sort(list, &(&1.name <= &2.name)) |> Enum.reverse()
        end
      end
      """

      result = fix(input)
      assert result =~ "Enum.sort"
      assert result =~ "Enum.reverse"
    end

    test "fixes multiple patterns independently" do
      input = """
      defmodule Example do
        def process(a, b) do
          x = a |> Enum.sort() |> Enum.reverse()
          y = Enum.reverse(Enum.sort(b))
          {x, y}
        end
      end
      """

      result = fix(input)
      assert result =~ "Enum.sort(:desc)"
      refute result =~ "Enum.reverse"
    end

    test "fixes fixable pattern while leaving custom comparator untouched" do
      input = """
      defmodule Example do
        def process(a, b) do
          x = a |> Enum.sort() |> Enum.reverse()
          y = Enum.sort(b, &(&1 >= &2)) |> Enum.reverse()
          {x, y}
        end
      end
      """

      result = fix(input)
      assert result =~ "a |> Enum.sort(:desc)"
      assert result =~ "&(&1 >= &2)"
      assert result =~ "Enum.reverse"
    end
  end
end
