defmodule Credence.Syntax.NoKeywordIfInTupleAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoKeywordIfInTuple

  defp analyze(code), do: NoKeywordIfInTuple.analyze(code)

  test "flags the unparseable code" do
    code = """
    defmodule Catalog.Ranked do
      def sort_products(products, direction) do
        Enum.sort_by(products, fn product ->
          {if direction == :asc, do: product.score, else: -product.score,
           product.name, product.id}
        end)
      end
    end
    """

    assert [%Issue{rule: :no_keyword_if_in_tuple, meta: %{line: 4}}] = analyze(code)
  end

  test "leaves good code alone" do
    code = """
    defmodule Catalog.Ranked do
      def sort_products(products, direction) do
        Enum.sort_by(products, fn product ->
          {(if direction == :asc, do: product.score, else: -product.score),
           product.name, product.id}
        end)
      end
    end
    """

    assert analyze(code) == []
  end
end
