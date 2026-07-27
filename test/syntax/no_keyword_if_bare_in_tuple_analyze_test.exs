defmodule Credence.Syntax.NoKeywordIfBareInTupleAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoKeywordIfBareInTuple

  defp analyze(code), do: NoKeywordIfBareInTuple.analyze(code)

  test "flags the unparseable code" do
    code = """
    defmodule M do
      def parse_page(params) do
        case params do
          %{"page" => page_val} when is_binary(page_val) ->
            case Integer.parse(page_val) do
              {num, _} -> {:ok, if num < 1, do: 1, else: num}
              :error -> {:ok, 1}
            end

          %{"page" => page_val} when is_integer(page_val) ->
            {:ok, if page_val < 1, do: 1, else: page_val}

          _ ->
            {:ok, 1}
        end
      end
    end
    """

    assert [%Issue{rule: :no_keyword_if_bare_in_tuple, meta: %{line: 6}}] = analyze(code)
  end

  test "leaves good code alone" do
    code = """
    defmodule M do
      def parse_page(params) do
        case params do
          %{"page" => page_val} when is_binary(page_val) ->
            case Integer.parse(page_val) do
              {num, _} -> {:ok, (if num < 1, do: 1, else: num)}
              :error -> {:ok, 1}
            end

          %{"page" => page_val} when is_integer(page_val) ->
            {:ok, (if page_val < 1, do: 1, else: page_val)}

          _ ->
            {:ok, 1}
        end
      end
    end
    """

    assert analyze(code) == []
  end
end
