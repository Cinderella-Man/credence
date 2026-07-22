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

  test "catch rides along into the try when after is present" do
    input = ~S"""
    defmodule CaseWithCatchAndAfter do
      def clean_up do
        case :ok do
          :ok -> :success
          _ -> :failure
        catch
          :throw, value -> value
        after
          IO.puts("done")
        end
      end
    end
    """

    expected = ~S"""
    defmodule CaseWithCatchAndAfter do
      def clean_up do
        try do
          case :ok do
            :ok -> :success
            _ -> :failure
          end
        catch
          :throw, value -> value
        after
          IO.puts("done")
        end
      end
    end
    """

    confirm_fix(fix(input, @message_after), expected)
  end

  test "else rides along into the try when rescue is present" do
    input = ~S"""
    defmodule CaseWithElseAndRescue do
      def clean_up do
        case :ok do
          :ok -> :success
          _ -> :failure
        else
          value -> value
        rescue
          _ -> :error
        end
      end
    end
    """

    expected = ~S"""
    defmodule CaseWithElseAndRescue do
      def clean_up do
        try do
          case :ok do
            :ok -> :success
            _ -> :failure
          end
        else
          value -> value
        rescue
          _ -> :error
        end
      end
    end
    """

    confirm_fix(fix(input, @message_rescue), expected)
  end

  test "leaves a case with only catch untouched (not this rule's diagnostic)" do
    input = ~S"""
    defmodule CaseWithOnlyCatch do
      def clean_up do
        case :ok do
          :ok -> :success
          _ -> :failure
        catch
          :throw, value -> value
        end
      end
    end
    """

    confirm_fix(fix(input, @message_after), input)
  end

  test "does not touch a plain nested case inside the broken one" do
    input = ~S"""
    defmodule Nested do
      def clean_up(x) do
        case x do
          :ok ->
            case x do
              :ok -> :inner
            end

          _ ->
            :failure
        after
          IO.puts("done")
        end
      end
    end
    """

    expected = ~S"""
    defmodule Nested do
      def clean_up(x) do
        try do
          case x do
            :ok ->
              case x do
                :ok -> :inner
              end

            _ ->
              :failure
          end
        after
          IO.puts("done")
        end
      end
    end
    """

    confirm_fix(fix(input, @message_after), expected)
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
