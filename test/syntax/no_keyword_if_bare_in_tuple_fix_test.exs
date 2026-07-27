defmodule Credence.Syntax.NoKeywordIfBareInTupleFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoKeywordIfBareInTuple

  defp analyze(code), do: NoKeywordIfBareInTuple.analyze(code)
  defp fix(code), do: NoKeywordIfBareInTuple.fix(code)

  test "fixes the syntax error" do
    input = """
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

    expected = """
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

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = """
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

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = """
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

    assert valid_syntax?(fix(input))
  end
end
