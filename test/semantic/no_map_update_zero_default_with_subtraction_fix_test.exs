defmodule Credence.Semantic.NoMapUpdateZeroDefaultWithSubtractionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoMapUpdateZeroDefaultWithSubtraction

  @message "Map.update with zero default and subtraction in callback"

  defp fix(source, message, line \\ 1) do
    NoMapUpdateZeroDefaultWithSubtraction.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes the source" do
    input = """
    defmodule M do
      def run do
        type = "debit"
        amount = 500.00

        balance_by_account = %{}

        Map.update(balance_by_account, "acct_1", 0, fn existing ->
          case type do
            "credit" -> existing + amount
            "debit" -> existing - amount
          end
        end)
      end
    end
    """

    expected = """
    defmodule M do
      def run do
        type = "debit"
        amount = 500.00

        balance_by_account = %{}

        signed_amount = if type == "credit", do: amount, else: -amount

        Map.update(balance_by_account, "acct_1", signed_amount, fn existing ->
          existing + amount
        end)
      end
    end
    """

    confirm_fix(fix(input, @message, 9), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule M do
      def run do
        type = "debit"
        amount = 500.00

        balance_by_account = %{}

        Map.update(balance_by_account, "acct_1", 0, fn existing ->
          case type do
            "credit" -> existing + amount
            "debit" -> existing - amount
          end
        end)
      end
    end
    """

    assert valid_syntax?(fix(input, @message, 9))
  end

  test "returns source unchanged when default is not literal zero" do
    input = """
    defmodule M do
      def run do
        type = "debit"
        amount = 500.00
        default = 0

        balance_by_account = %{}

        Map.update(balance_by_account, "acct_1", default, fn existing ->
          case type do
            "credit" -> existing + amount
            "debit" -> existing - amount
          end
        end)
      end
    end
    """

    result = fix(input, @message, 10)
    confirm_fix(result, input)
  end

  test "returns source unchanged when callback has no subtraction" do
    input = """
    defmodule M do
      def run do
        type = "debit"
        amount = 500.00

        balance_by_account = %{}

        Map.update(balance_by_account, "acct_1", 0, fn existing ->
          case type do
            "credit" -> existing + amount
            "debit" -> existing + amount
          end
        end)
      end
    end
    """

    result = fix(input, @message, 9)
    confirm_fix(result, input)
  end

  test "works with reversed branch order" do
    input = """
    defmodule M do
      def run do
        type = "debit"
        amount = 500.00

        balance_by_account = %{}

        Map.update(balance_by_account, "acct_1", 0, fn existing ->
          case type do
            "debit" -> existing - amount
            "credit" -> existing + amount
          end
        end)
      end
    end
    """

    expected = """
    defmodule M do
      def run do
        type = "debit"
        amount = 500.00

        balance_by_account = %{}

        signed_amount = if type == "credit", do: amount, else: -amount

        Map.update(balance_by_account, "acct_1", signed_amount, fn existing ->
          existing + amount
        end)
      end
    end
    """

    confirm_fix(fix(input, @message, 9), expected)
  end
end
