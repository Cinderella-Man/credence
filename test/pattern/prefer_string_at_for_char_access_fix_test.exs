defmodule Credence.Pattern.PreferStringAtForCharAccessFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferStringAtForCharAccess

  test "rewrites the anti-pattern in the cells_in_range example" do
    input = """
    defmodule Solution do
      def cells_in_range(range_string) do
        <<col_start::binary-size(1), row_start::binary-size(1), ":", col_end::binary-size(1), row_end::binary-size(1)>> = range_string
        col_start_code = col_start |> String.to_charlist() |> hd()
        col_end_code = col_end |> String.to_charlist() |> hd()
        row_start_num = String.to_integer(row_start)
        row_end_num = String.to_integer(row_end)
        for col_code <- col_start_code..col_end_code, row <- row_start_num..row_end_num do
          col_letter = List.to_string([col_code])
          "\#{col_letter}\#{row}"
        end
      end
    end
    """

    expected = """
    defmodule Solution do
      def cells_in_range(range_string) do
        <<col_start::binary-size(1), row_start::binary-size(1), ":", col_end::binary-size(1), row_end::binary-size(1)>> = range_string
        col_start_code = col_start |> String.to_charlist() |> hd()
        col_end_code = col_end |> String.to_charlist() |> hd()
        row_start_num = String.to_integer(row_start)
        row_end_num = String.to_integer(row_end)
        for col_code <- col_start_code..col_end_code, row <- row_start_num..row_end_num do
          "\#{<<col_code::utf8>>}\#{row}"
        end
      end
    end
    """

    assert fix(PreferStringAtForCharAccess, input) == expected
  end

  test "rewrites a simple List.to_string assignment" do
    input = """
    defmodule M do
      def f(code) do
        letter = List.to_string([code])
        letter
      end
    end
    """

    expected = """
    defmodule M do
      def f(code) do
        <<code::utf8>>
      end
    end
    """

    assert fix(PreferStringAtForCharAccess, input) == expected
  end

  test "does not modify code that is already correct" do
    code = """
    defmodule M do
      def f(x) do
        <<x::utf8>>
      end
    end
    """

    assert fix(PreferStringAtForCharAccess, code) == code
  end
end
