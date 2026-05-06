defmodule Credence.Pattern.NoListToTupleForAccessTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoListToTupleForAccess.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoListToTupleForAccess.fix(code, [])
  end

  defp assert_fix(input, expected) do
    result = fix(input)
    # Both sides go through Code.format_string! so formatting
    # differences (trailing newlines, whitespace) are normalised.
    formatted_expected = expected |> Code.format_string!() |> IO.iodata_to_binary()
    assert result == formatted_expected
  end

  describe "fixable?" do
    test "returns true" do
      assert Credence.Pattern.NoListToTupleForAccess.fixable?() == true
    end
  end

  describe "check/2" do
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

  describe "fix/2" do
    test "converts direct List.to_tuple + elem to Enum.at" do
      assert_fix(
        """
        defmodule Example do
          def run(list) do
            t = List.to_tuple(list)
            elem(t, 0)
          end
        end
        """,
        """
        defmodule Example do
          def run(list) do
            t = List.to_tuple(list)
            Enum.at(list, 0)
          end
        end
        """
      )
    end

    test "converts piped List.to_tuple + elem to Enum.at" do
      assert_fix(
        """
        defmodule Example do
          def run(list) do
            t = list |> List.to_tuple()
            elem(t, 0)
          end
        end
        """,
        """
        defmodule Example do
          def run(list) do
            t = list |> List.to_tuple()
            Enum.at(list, 0)
          end
        end
        """
      )
    end

    test "converts multiple elem calls on same tuple variable" do
      assert_fix(
        """
        defmodule Example do
          def run(list) do
            t = List.to_tuple(list)
            a = elem(t, 0)
            b = elem(t, 1)
            {a, b}
          end
        end
        """,
        """
        defmodule Example do
          def run(list) do
            t = List.to_tuple(list)
            a = Enum.at(list, 0)
            b = Enum.at(list, 1)
            {a, b}
          end
        end
        """
      )
    end

    test "leaves List.to_tuple binding when t is still used elsewhere" do
      assert_fix(
        """
        defmodule Example do
          def run(list) do
            t = List.to_tuple(list)
            size = tuple_size(t)
            first = elem(t, 0)
            {first, size}
          end
        end
        """,
        """
        defmodule Example do
          def run(list) do
            t = List.to_tuple(list)
            size = tuple_size(t)
            first = Enum.at(list, 0)
            {first, size}
          end
        end
        """
      )
    end

    test "returns source unchanged when no List.to_tuple bindings found" do
      code = """
      defmodule Example do
        def run(list) do
          List.to_tuple(list)
        end
      end
      """

      assert fix(code) == code
    end

    test "does not touch elem on a variable not from List.to_tuple" do
      code = """
      defmodule Example do
        def run(tuple) do
          elem(tuple, 0)
        end
      end
      """

      assert fix(code) == code
    end

    test "handles long pipeline ending with List.to_tuple" do
      result =
        fix("""
        defmodule Example do
          def run(str) do
            t =
              str
              |> String.trim()
              |> String.upcase()
              |> List.to_tuple()

            elem(t, 0)
          end
        end
        """)

      assert result =~ "Enum.at("
      assert result =~ "String.trim()"
      assert result =~ "String.upcase()"
      refute result =~ "elem(t"
    end
  end

  describe "edge cases" do
    test "does NOT detect piped elem: t |> elem(0)" do
      # Known gap: piped form has different AST shape
      code = """
      defmodule PipedElem do
        def run(list) do
          t = List.to_tuple(list)
          t |> elem(0)
        end
      end
      """

      # Currently returns [] because the AST for `t |> elem(0)` is
      # {:|>, _, [t, {:elem, _, [0]}]}, not {:elem, _, [t, 0]}
      assert check(code) == []
    end

    test "does NOT detect direct pipeline without binding" do
      # Known gap: no variable binding means Pass 1 finds nothing
      code = """
      defmodule DirectPipe do
        def run(list) do
          list |> List.to_tuple() |> elem(0)
        end
      end
      """

      assert check(code) == []
    end

    test "FALSE POSITIVE: same variable name in different functions" do
      code = """
      defmodule ScopeBug do
        def make(list) do
          t = List.to_tuple(list)
          t
        end

        def first(t) do
          elem(t, 0)
        end
      end
      """

      issues = check(code)
      # This flags `elem(t, 0)` in `first/1` even though `t` there is
      # a parameter, unrelated to `List.to_tuple` in `make/1`.
      # Documenting the false positive
      assert length(issues) == 1
    end

    test "FALSE POSITIVE: rebinding does not clear the tracking" do
      code = """
      defmodule RebindBug do
        def run(list) do
          t = List.to_tuple(list)
          t = String.graphemes("hello")
          elem(t, 0)
        end
      end
      """

      issues = check(code)
      # Flags `elem(t, 0)` even though `t` was rebound to a list of graphemes.
      # Documenting the false positive
      assert length(issues) == 1
    end

    test "FALSE POSITIVE: different t inside anonymous function" do
      code = """
      defmodule NestedScope do
        def run(list) do
          t = List.to_tuple(list)
          fn t -> elem(t, 0) end
        end
      end
      """

      issues = check(code)
      # Flags the inner `elem(t, 0)` even though `t` is a different binding.
      # Documenting the false positive
      assert length(issues) == 1
    end
  end
end
