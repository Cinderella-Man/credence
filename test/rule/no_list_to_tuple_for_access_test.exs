defmodule Credence.Rule.NoListToTupleForAccessTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoListToTupleForAccess.check(ast, [])
  end

  describe "NoListToTupleForAccess" do
    test "passes code that uses pattern matching on a list" do
      code = """
      defmodule GoodAccess do
        def first_and_last(list) do
          [first | _] = list
          last = List.last(list)
          {first, last}
        end
      end
      """

      assert check(code) == []
    end

    test "passes List.to_tuple without elem access" do
      code = """
      defmodule SafeTuple do
        def to_tuple(list) do
          List.to_tuple(list)
        end
      end
      """

      assert check(code) == []
    end

    test "passes elem on a tuple not from List.to_tuple" do
      code = """
      defmodule SafeElem do
        def process(tuple) do
          elem(tuple, 0)
        end
      end
      """

      assert check(code) == []
    end

    test "detects List.to_tuple then elem on same variable" do
      code = """
      defmodule BadTupleAccess do
        def first_two(list) do
          t = List.to_tuple(list)
          {elem(t, 0), elem(t, 1)}
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_list_to_tuple_for_access
      assert issue.severity == :warning
      assert issue.message =~ "List.to_tuple"
      assert issue.message =~ "pattern matching"
      assert issue.meta.line != nil
    end

    test "detects piped List.to_tuple then elem" do
      code = """
      defmodule BadPiped do
        def get_char(graphemes, idx) do
          t = graphemes |> List.to_tuple()
          elem(t, idx)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_list_to_tuple_for_access
    end

    test "reports once per variable even with multiple elem calls" do
      code = """
      defmodule MultipleElems do
        def process(list) do
          t = List.to_tuple(list)
          a = elem(t, 0)
          b = elem(t, 1)
          c = elem(t, 2)
          a + b + c
        end
      end
      """

      issues = check(code)

      # Should deduplicate to one issue per variable
      assert length(issues) == 1
    end

    test "ignores elem on a different variable" do
      code = """
      defmodule DifferentVars do
        def process(list, other_tuple) do
          _t = List.to_tuple(list)
          elem(other_tuple, 0)
        end
      end
      """

      assert check(code) == []
    end
  end
end
