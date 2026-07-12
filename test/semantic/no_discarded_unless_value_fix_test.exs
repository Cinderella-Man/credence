defmodule Credence.Semantic.NoDiscardedUnlessValueFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoDiscardedUnlessValue

  @real_message "unless expression result is unused"

  defp fix(source, line \\ 1) do
    NoDiscardedUnlessValue.fix(source, %{
      severity: :warning,
      message: @real_message,
      position: {line, 1}
    })
  end

  @input """
  defmodule M do
    def sort_and_check(sort, opts) do
      sort = sort || "id"
      direction = opts[:direction] || :asc

      unless sort in ["name", "price", "id", "category"] do
        {:error, :invalid_sort_field}
      end

      {:ok, %{sort: sort, direction: direction}}
    end
  end
  """

  @expected """
  defmodule M do
    def sort_and_check(sort, opts) do
      sort = sort || "id"
      direction = opts[:direction] || :asc

      if sort not in ["name", "price", "id", "category"] do
        {:error, :invalid_sort_field}
      else
        {:ok, %{sort: sort, direction: direction}}
      end
    end
  end
  """

  test "converts discarded unless to if/else" do
    confirm_fix(fix(@input), @expected)
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix(@input))
  end

  test "ignores unless that already has else" do
    input = """
    defmodule Example do
      def check(value) do
        unless value == :ok do
          {:error, :bad}
        else
          :ok
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "ignores unless that is the last expression" do
    input = """
    defmodule Example do
      def check(value) do
        unless value == :ok do
          {:error, :bad}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "handles unless followed by multiple expressions" do
    input = """
    defmodule Example do
      def check(value) do
        unless value == :ok do
          {:error, :bad}
        end

        Logger.info("checked")
        {:ok, value}
      end
    end
    """

    expected = """
    defmodule Example do
      def check(value) do
        if not (value == :ok) do
          {:error, :bad}
        else
          Logger.info("checked")
          {:ok, value}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "handles unless as first expression in block" do
    input = """
    defmodule Example do
      def check(value) do
        unless value == :ok do
          raise "bad value"
        end

        :ok
      end
    end
    """

    expected = """
    defmodule Example do
      def check(value) do
        if not (value == :ok) do
          raise "bad value"
        else
          :ok
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "handles nested unless — transforms inner discarded unless" do
    input = """
    defmodule Example do
      def check(a, b) do
        unless a do
          unless b do
            {:error, :both_bad}
          end

          {:error, :a_bad}
        end

        :ok
      end
    end
    """

    expected = """
    defmodule Example do
      def check(a, b) do
        if not a do
          if not b do
            {:error, :both_bad}
          else
            {:error, :a_bad}
          end
        else
          :ok
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "multiple fix passes converge" do
    input = """
    defmodule Example do
      def check(a, b) do
        unless a do
          unless b do
            {:error, :both_bad}
          end

          {:error, :a_bad}
        end

        :ok
      end
    end
    """

    # First pass fixes inner unless, second pass fixes outer
    first_pass = fix(input)
    second_pass = fix(first_pass)
    third_pass = fix(second_pass)

    # Should converge after 2 passes
    confirm_fix(second_pass, third_pass)
    assert valid_syntax?(third_pass)
  end
end
