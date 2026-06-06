defmodule Credence.Pattern.NoNestedEnumOnSameEnumerableCheckTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoNestedEnumOnSameEnumerable

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoNestedEnumOnSameEnumerable.check(ast, [])
  end

  describe "check/2" do
    test "detects member? inside map" do
      code = """
      defmodule Bad do
        def process(list) do
          Enum.map(list, fn x ->
            Enum.member?(list, x + 1)
          end)
        end
      end
      """

      [issue] = check(code)
      assert %Issue{} = issue
      assert issue.rule == :no_nested_enum_on_same_enumerable
      assert issue.message =~ "MapSet"
      assert issue.message =~ "O(n²)"
    end

    test "does not flag different enumerables" do
      code = """
      defmodule Good do
        def process(a, b) do
          Enum.map(a, fn x ->
            Enum.member?(b, x)
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag sibling def clauses sharing a parameter name" do
      code = """
      defmodule Sibling do
        def f1([h | _t], xs), do: Enum.map(xs, fn x -> x + h end)
        def f1([], xs),       do: Enum.map(xs, fn x -> x * 2 end)
      end
      """

      assert check(code) == []
    end

    test "does not flag siblings inside separate function bodies" do
      code = """
      defmodule TwoFns do
        def a(items), do: Enum.map(items, & &1 + 1)
        def b(items), do: Enum.filter(items, & &1 > 0)
      end
      """

      assert check(code) == []
    end

    test "still flags real nested Enum on the same enumerable" do
      code = """
      defmodule Bad do
        def process(list) do
          Enum.map(list, fn x ->
            Enum.member?(list, x + 1)
          end)
        end
      end
      """

      assert [%Issue{rule: :no_nested_enum_on_same_enumerable}] = check(code)
    end
  end
end
