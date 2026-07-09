defmodule Credence.Semantic.FixAfterOrRescueInCaseFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixAfterOrRescueInCase

  @message_after "unexpected option :after in \"case\""
  @message_rescue "unexpected option :rescue in \"case\""

  defp fix(source, message, line \\ 1) do
    FixAfterOrRescueInCase.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "wraps case-after in try" do
    input = ~S"""
    defmodule CaseWithAfter do
      def clean_up do
        case :ok do
          :ok -> :success
          _ -> :failure
        after
          IO.puts("done")
        end
      end
    end
    """

    expected = ~S"""
    defmodule CaseWithAfter do
      def clean_up do
        try do
          case :ok do
            :ok -> :success
            _ -> :failure
          end
        after
          IO.puts("done")
        end
      end
    end
    """

    confirm_fix(fix(input, @message_after), expected)
  end

  test "wraps case-rescue in try" do
    input = ~S"""
    defmodule CaseWithRescue do
      def clean_up do
        case :ok do
          :ok -> :success
          _ -> :failure
        rescue
          _ -> :error
        end
      end
    end
    """

    expected = ~S"""
    defmodule CaseWithRescue do
      def clean_up do
        try do
          case :ok do
            :ok -> :success
            _ -> :failure
          end
        rescue
          _ -> :error
        end
      end
    end
    """

    confirm_fix(fix(input, @message_rescue), expected)
  end

  test "wraps case-rescue-after in try" do
    input = ~S"""
    defmodule CaseWithBoth do
      def clean_up do
        case :ok do
          :ok -> :success
          _ -> :failure
        rescue
          _ -> :error
        after
          IO.puts("done")
        end
      end
    end
    """

    expected = ~S"""
    defmodule CaseWithBoth do
      def clean_up do
        try do
          case :ok do
            :ok -> :success
            _ -> :failure
          end
        rescue
          _ -> :error
        after
          IO.puts("done")
        end
      end
    end
    """

    confirm_fix(fix(input, @message_after), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule ParseCheck do
      def check do
        case :ok do
          :ok -> :success
          _ -> :failure
        after
          IO.puts("done")
        end
      end
    end
    """

    assert valid_syntax?(fix(input, @message_after))
  end

  test "returns source unchanged when case has no after or rescue" do
    input = ~S"""
    defmodule NormalCase do
      def check(x) do
        case x do
          :ok -> :success
          _ -> :failure
        end
      end
    end
    """

    confirm_fix(fix(input, @message_after), input)
  end
end
