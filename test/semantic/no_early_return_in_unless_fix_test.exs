defmodule Credence.Semantic.NoEarlyReturnInUnlessFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoEarlyReturnInUnless

  @message "undefined function return/1 (expected Catalog.Faceted to define such a function or for it to be imported, but none are available)"

  defp fix(source, line \\ 1) do
    NoEarlyReturnInUnless.fix(source, %{severity: :error, message: @message, position: {line, 1}})
  end

  test "restructures unless/return to if/else with rest as do-body" do
    input = ~S"""
    defmodule Catalog.Faceted do
      def search(products, params) do
        unless Map.get(params, "sort", "id") in ["name", "price", "id", "category"] do
          return {:error, :invalid_sort_field}
        end

        Enum.map(products, fn p ->
          %{id: p.id, name: p.name, category: p.category, price: p.price_cents, tags: p.tags}
        end)
      end
    end
    """

    expected = ~S"""
    defmodule Catalog.Faceted do
      def search(products, params) do
        if Map.get(params, "sort", "id") in ["name", "price", "id", "category"] do
          Enum.map(products, fn p ->
            %{id: p.id, name: p.name, category: p.category, price: p.price_cents, tags: p.tags}
          end)
        else
          {:error, :invalid_sort_field}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "restructures simple unless/return" do
    input = ~S"""
    defmodule SimpleExample do
      def validate(value) do
        unless is_integer(value) do
          return {:error, :not_integer}
        end

        {:ok, value}
      end
    end
    """

    expected = ~S"""
    defmodule SimpleExample do
      def validate(value) do
        if is_integer(value) do
          {:ok, value}
        else
          {:error, :not_integer}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule ParseCheck do
      def check(x) do
        unless x > 0 do
          return {:error, :bad}
        end

        {:ok, x}
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "returns source unchanged when no unless/return pattern" do
    input = ~S"""
    defmodule CleanModule do
      def check(x) do
        if x > 0 do
          {:ok, x}
        else
          {:error, :bad}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged when unless body has no return" do
    input = ~S"""
    defmodule NoReturn do
      def check(x) do
        unless x > 0 do
          IO.puts("bad")
        end

        {:ok, x}
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not match unless/return inside nested block" do
    input = ~S"""
    defmodule NestedUnless do
      def check(x) do
        y =
          unless x > 0 do
            return {:error, :bad}
          end

        {:ok, y}
      end
    end
    """

    confirm_fix(fix(input), input)
  end
end
