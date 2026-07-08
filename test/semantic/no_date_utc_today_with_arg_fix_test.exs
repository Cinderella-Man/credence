defmodule Credence.Semantic.NoDateUtcTodayWithArgFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoDateUtcTodayWithArg

  @real_message "this clause for process_file/2 cannot match because a previous clause at line 30 always matches"

  defp fix(source, message, line \\ 1) do
    NoDateUtcTodayWithArg.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "strips spurious argument from Date.utc_today/1" do
    input = """
    defmodule Example do
      def daily_volume(transaction) do
        timestamp = transaction.timestamp

        date_key =
          case Date.utc_today(timestamp) do
            {year, month, day} ->
              {year, month, day}
          end

        Map.put(%{}, date_key, transaction.amount)
      end
    end
    """

    expected = """
    defmodule Example do
      def daily_volume(transaction) do
        timestamp = transaction.timestamp

        date_key =
          case Date.utc_today() do
            {year, month, day} ->
              {year, month, day}
          end

        Map.put(%{}, date_key, transaction.amount)
      end
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def daily_volume(transaction) do
        case Date.utc_today(transaction.timestamp) do
          {year, month, day} -> {year, month, day}
        end
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message))
  end

  test "returns source unchanged when no Date.utc_today with arg present" do
    input = """
    defmodule Clean do
      def today do
        Date.utc_today()
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
