defmodule Credence.Semantic.FixAfterOrRescueInCaseFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixAfterOrRescueInCase

  @message_after "unexpected option :after in \"case\""
  @message_rescue "unexpected option :rescue in \"case\""
  @message_catch "unexpected option :catch in \"case\""

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

  # An `else` vetoes the whole rewrite. A `try`'s `else` matches the success
  # value of the body, not the fallthrough of the `case`, so moving it changes
  # what the program returns. Both shapes below were verified by execution:
  # a catch-all `else` turns :success into :err, and a non-exhaustive one
  # raises TryClauseError where the original merely failed to compile.
  test "refuses the rewrite when else is present, even alongside rescue" do
    input = ~S"""
    defmodule CaseWithElseAndRescue do
      def clean_up do
        case :ok do
          :ok -> :success
          _ -> :failure
        else
          _ -> :err
        rescue
          _ -> :error
        end
      end
    end
    """

    confirm_fix(fix(input, @message_rescue), input)
  end

  test "refuses the rewrite when else is present alongside after" do
    input = ~S"""
    defmodule CaseWithElseAndAfter do
      def clean_up do
        case :ok do
          :ok -> :success
        else
          _ -> :err
        after
          IO.puts("done")
        end
      end
    end
    """

    confirm_fix(fix(input, @message_after), input)
  end

  test "wraps case-catch in try" do
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

    expected = ~S"""
    defmodule CaseWithOnlyCatch do
      def clean_up do
        try do
          case :ok do
            :ok -> :success
            _ -> :failure
          end
        catch
          :throw, value -> value
        end
      end
    end
    """

    confirm_fix(fix(input, @message_catch), expected)
  end

  test "the decline yields the slot rather than consuming the diagnostic" do
    with_else = ~S"""
    defmodule Yielding do
      def clean_up do
        case :ok do
          :ok -> :success
        else
          _ -> :err
        after
          IO.puts("done")
        end
      end
    end
    """

    diag = %{severity: :error, message: @message_after, position: {1, 1}}
    refute FixAfterOrRescueInCase.should_report?(diag, with_else)

    without_else = ~S"""
    defmodule Reporting do
      def clean_up do
        case :ok do
          :ok -> :success
        after
          IO.puts("done")
        end
      end
    end
    """

    assert FixAfterOrRescueInCase.should_report?(diag, without_else)
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
