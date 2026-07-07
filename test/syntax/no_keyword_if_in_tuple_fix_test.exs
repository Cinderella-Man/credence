defmodule Credence.Syntax.NoKeywordIfInTupleFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoKeywordIfInTuple

  defp analyze(code), do: NoKeywordIfInTuple.analyze(code)
  defp fix(code), do: NoKeywordIfInTuple.fix(code)

  test "fixes the syntax error" do
    input = """
    defmodule Catalog.Ranked do
      def sort_products(products, direction) do
        Enum.sort_by(products, fn product ->
          {if direction == :asc, do: product.score, else: -product.score,
           product.name, product.id}
        end)
      end
    end
    """

    expected = """
    defmodule Catalog.Ranked do
      def sort_products(products, direction) do
        Enum.sort_by(products, fn product ->
          {(if direction == :asc, do: product.score, else: -product.score),
           product.name, product.id}
        end)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = """
    defmodule Catalog.Ranked do
      def sort_products(products, direction) do
        Enum.sort_by(products, fn product ->
          {if direction == :asc, do: product.score, else: -product.score,
           product.name, product.id}
        end)
      end
    end
    """

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Catalog.Ranked do
      def sort_products(products, direction) do
        Enum.sort_by(products, fn product ->
          {if direction == :asc, do: product.score, else: -product.score,
           product.name, product.id}
        end)
      end
    end
    """

    assert valid_syntax?(fix(input))
  end
end
