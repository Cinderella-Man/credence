defmodule Credence.Semantic.NoRescueInCondFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoRescueInCond
  alias Credence.RuleHelpers

  @message_rescue "unexpected option :rescue in \"cond\""
  @message_catch "unexpected option :catch in \"cond\""

  defp fix(source, message, line \\ 1) do
    NoRescueInCond.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  test "repairs a real compiler diagnostic through the Semantic pipeline" do
    input = ~S"""
    defmodule NoRescueInCondPipelineFixture do
      def run do
        cond do
          true -> :ok
        rescue
          _ -> :error
        end
      end
    end
    """

    expected = ~S"""
    defmodule NoRescueInCondPipelineFixture do
      def run do
        try do
          cond do
            true -> :ok
          end
        rescue
          _ -> :error
        end
      end
    end
    """

    control = String.replace(expected, "PipelineFixture", "PipelineControl")

    assert {:error, diagnostics} = RuleHelpers.compile_and_capture(input)
    assert Enum.any?(diagnostics, &NoRescueInCond.match?/1)

    {emitted, applied} = Credence.Semantic.fix_with_trace(input)

    confirm_fix(emitted, expected)
    assert applied == [{NoRescueInCond, 1}]
    assert RuleHelpers.compile_and_capture(emitted) == RuleHelpers.compile_and_capture(control)
  end

  test "does not rewrite cond syntax stored inside quote" do
    input = ~S"""
    defmodule NoRescueInCondQuotedData do
      def broken do
        cond do
          true -> :ok
        rescue
          _ -> :error
        end
      end

      def data do
        quote do
          cond do
            true -> :quoted_ok
          rescue
            _ -> :quoted_error
          end
        end
      end
    end
    """

    expected = ~S"""
    defmodule NoRescueInCondQuotedData do
      def broken do
        try do
          cond do
            true -> :ok
          end
        rescue
          _ -> :error
        end
      end

      def data do
        quote do
          cond do
            true -> :quoted_ok
          rescue
            _ -> :quoted_error
          end
        end
      end
    end
    """

    confirm_fix(fix(input, @message_rescue), expected)
  end

  test "wraps cond-rescue in try" do
    input = ~S"""
    defmodule BadRescueInCond do
      def run do
        cond do
          true -> :ok
        rescue
          e -> {:error, e}
        end
      end
    end
    """

    expected = ~S"""
    defmodule BadRescueInCond do
      def run do
        try do
          cond do
            true -> :ok
          end
        rescue
          e -> {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input, @message_rescue), expected)
  end

  test "wraps cond-catch in try" do
    input = ~S"""
    defmodule CondWithCatch do
      def run do
        cond do
          true -> :ok
        catch
          e -> {:error, e}
        end
      end
    end
    """

    expected = ~S"""
    defmodule CondWithCatch do
      def run do
        try do
          cond do
            true -> :ok
          end
        catch
          e -> {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input, @message_catch), expected)
  end

  test "wraps cond-rescue-catch in try" do
    input = ~S"""
    defmodule CondWithBoth do
      def run do
        cond do
          true -> :ok
        rescue
          e -> {:error, e}
        catch
          e -> {:error, e}
        end
      end
    end
    """

    expected = ~S"""
    defmodule CondWithBoth do
      def run do
        try do
          cond do
            true -> :ok
          end
        rescue
          e -> {:error, e}
        catch
          e -> {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input, @message_rescue), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule ParseCheck do
      def check do
        cond do
          true -> :ok
        rescue
          e -> {:error, e}
        end
      end
    end
    """

    assert valid_syntax?(fix(input, @message_rescue))
  end

  test "after rides along into the try when rescue is present" do
    input = ~S"""
    defmodule CondWithRescueAndAfter do
      def run do
        cond do
          true -> :ok
        rescue
          e -> {:error, e}
        after
          IO.puts("done")
        end
      end
    end
    """

    expected = ~S"""
    defmodule CondWithRescueAndAfter do
      def run do
        try do
          cond do
            true -> :ok
          end
        rescue
          e -> {:error, e}
        after
          IO.puts("done")
        end
      end
    end
    """

    confirm_fix(fix(input, @message_rescue), expected)
  end

  test "else rides along into the try when catch is present" do
    input = ~S"""
    defmodule CondWithElseAndCatch do
      def run(x) do
        cond do
          x > 0 -> :ok
        else
          v -> v
        catch
          :throw, v -> v
        end
      end
    end
    """

    expected = ~S"""
    defmodule CondWithElseAndCatch do
      def run(x) do
        try do
          cond do
            x > 0 -> :ok
          end
        else
          v -> v
        catch
          :throw, v -> v
        end
      end
    end
    """

    confirm_fix(fix(input, @message_catch), expected)
  end

  test "leaves a cond with only after untouched (not this rule's diagnostic)" do
    input = ~S"""
    defmodule CondWithOnlyAfter do
      def run do
        cond do
          true -> :ok
        after
          IO.puts("done")
        end
      end
    end
    """

    confirm_fix(fix(input, @message_rescue), input)
  end

  test "leaves a cond with only else untouched (not this rule's diagnostic)" do
    input = ~S"""
    defmodule CondWithOnlyElse do
      def run(x) do
        cond do
          x > 0 -> :ok
        else
          v -> v
        end
      end
    end
    """

    confirm_fix(fix(input, @message_rescue), input)
  end

  test "does not touch a plain nested cond inside the broken one" do
    input = ~S"""
    defmodule Nested do
      def run(x) do
        cond do
          x > 0 ->
            cond do
              x > 5 -> :big
              true -> :small
            end

          true ->
            :neg
        rescue
          e -> {:error, e}
        end
      end
    end
    """

    expected = ~S"""
    defmodule Nested do
      def run(x) do
        try do
          cond do
            x > 0 ->
              cond do
                x > 5 -> :big
                true -> :small
              end

            true ->
              :neg
          end
        rescue
          e -> {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input, @message_rescue), expected)
  end

  test "leaves a valid try wrapping a cond alone" do
    input = ~S"""
    defmodule AlreadyGood do
      def run(x) do
        try do
          cond do
            x > 0 -> :pos
            true -> :other
          end
        rescue
          e -> {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input, @message_rescue), input)
  end

  test "returns source unchanged when cond has no rescue or catch" do
    input = ~S"""
    defmodule NormalCond do
      def check(x) do
        cond do
          x > 0 -> :positive
          x < 0 -> :negative
          true -> :zero
        end
      end
    end
    """

    confirm_fix(fix(input, @message_rescue), input)
  end
end
