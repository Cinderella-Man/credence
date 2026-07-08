defmodule Credence.Semantic.NoReturnFnInConditionalFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoReturnFnInConditional

  @message "undefined function return/1 (expected ReturnInUnless to define such a function or for it to be imported, but none are available)"

  defp fix(source, line \\ 1) do
    NoReturnFnInConditional.fix(source, %{severity: :error, message: @message, position: {line, 1}})
  end

  test "restructures chained unless/return guards into nested if/else" do
    input = ~S"""
    defmodule ReturnInUnless do
      @types [:percentage, :fixed_amount, :free_shipping]

      def validate(attrs) do
        type = Map.get(attrs, :type)
        value = Map.get(attrs, :value)

        unless type in @types do
          return {:error, :invalid_type}
        end

        unless is_integer(value) and value >= 0 do
          return {:error, :invalid_value}
        end

        {:ok, attrs}
      end
    end
    """

    expected = ~S"""
    defmodule ReturnInUnless do
      @types [:percentage, :fixed_amount, :free_shipping]

      def validate(attrs) do
        type = Map.get(attrs, :type)
        value = Map.get(attrs, :value)

        if type not in @types do
          {:error, :invalid_type}
        else
          unless is_integer(value) and value >= 0 do
            {:error, :invalid_value}
          else
            {:ok, attrs}
          end
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule ParseCheck do
      def validate(x) do
        unless x > 0 do
          return {:error, :bad}
        end

        unless x < 100 do
          return {:error, :too_big}
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
end
