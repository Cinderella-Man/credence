defmodule Credence.Semantic.NoRescueInWithExpressionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1, compiles?: 1]

  alias Credence.Semantic.NoRescueInWithExpression

  @message_rescue ~S(unexpected option :rescue in "with")
  @message_catch ~S(unexpected option :catch in "with")

  defp fix(source, message \\ @message_rescue, line \\ 1) do
    NoRescueInWithExpression.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "wraps with-rescue in try" do
    input = ~S"""
    defmodule Sample do
      def run(key) do
        with {:ok, raw} <- fetch(key) do
          {:ok, raw}
        rescue
          _ -> {:error, :boom}
        end
      end
    end
    """

    expected = ~S"""
    defmodule Sample do
      def run(key) do
        try do
          with {:ok, raw} <- fetch(key) do
            {:ok, raw}
          end
        rescue
          _ -> {:error, :boom}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "wraps with-catch in try" do
    input = ~S"""
    defmodule Sample do
      def run(key) do
        with {:ok, raw} <- fetch(key) do
          {:ok, raw}
        catch
          :throw, value -> {:error, value}
        end
      end
    end
    """

    expected = ~S"""
    defmodule Sample do
      def run(key) do
        try do
          with {:ok, raw} <- fetch(key) do
            {:ok, raw}
          end
        catch
          :throw, value -> {:error, value}
        end
      end
    end
    """

    confirm_fix(fix(input, @message_catch), expected)
  end

  test "keeps both rescue and catch, in source order" do
    input = ~S"""
    defmodule Sample do
      def run(key) do
        with {:ok, raw} <- fetch(key) do
          {:ok, raw}
        rescue
          e in ArgumentError -> {:error, Exception.message(e)}
        catch
          kind, value -> {:error, {kind, value}}
        end
      end
    end
    """

    expected = ~S"""
    defmodule Sample do
      def run(key) do
        try do
          with {:ok, raw} <- fetch(key) do
            {:ok, raw}
          end
        rescue
          e in ArgumentError -> {:error, Exception.message(e)}
        catch
          kind, value -> {:error, {kind, value}}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "an existing else stays on the with — it is valid there and means something else on try" do
    input = ~S"""
    defmodule Sample do
      def run(key) do
        with {:ok, raw} <- fetch(key) do
          {:ok, raw}
        rescue
          _ -> {:error, :boom}
        else
          {:error, reason} -> {:error, reason}
        end
      end
    end
    """

    expected = ~S"""
    defmodule Sample do
      def run(key) do
        try do
          with {:ok, raw} <- fetch(key) do
            {:ok, raw}
          else
            {:error, reason} -> {:error, reason}
          end
        rescue
          _ -> {:error, :boom}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "an after clause rides along into the try" do
    input = ~S"""
    defmodule Sample do
      def run(key) do
        with {:ok, raw} <- fetch(key) do
          {:ok, raw}
        rescue
          _ -> {:error, :boom}
        after
          IO.puts("done")
        end
      end
    end
    """

    expected = ~S"""
    defmodule Sample do
      def run(key) do
        try do
          with {:ok, raw} <- fetch(key) do
            {:ok, raw}
          end
        rescue
          _ -> {:error, :boom}
        after
          IO.puts("done")
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "keeps every <- and = clause of a multi-clause with" do
    input = ~S"""
    defmodule Sample do
      def run(key) do
        with {:ok, raw} <- fetch(key),
             trimmed = String.trim(raw),
             {:ok, dt} <- DateTime.from_iso8601(trimmed) do
          {:ok, dt}
        rescue
          _ -> {:error, :boom}
        end
      end
    end
    """

    expected = ~S"""
    defmodule Sample do
      def run(key) do
        try do
          with {:ok, raw} <- fetch(key),
               trimmed = String.trim(raw),
               {:ok, dt} <- DateTime.from_iso8601(trimmed) do
            {:ok, dt}
          end
        rescue
          _ -> {:error, :boom}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "leaves a plain with alone" do
    input = ~S"""
    defmodule Sample do
      def run(key) do
        with {:ok, raw} <- fetch(key) do
          {:ok, raw}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "leaves a with that only has else alone" do
    input = ~S"""
    defmodule Sample do
      def run(key) do
        with {:ok, raw} <- fetch(key) do
          {:ok, raw}
        else
          {:error, reason} -> {:error, reason}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "leaves a with whose only invalid option is after alone (another diagnostic owns it)" do
    input = ~S"""
    defmodule Sample do
      def run(key) do
        with {:ok, raw} <- fetch(key) do
          {:ok, raw}
        after
          IO.puts("done")
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "leaves a legitimate try-rescue alone" do
    input = ~S"""
    defmodule Sample do
      def run(key) do
        try do
          fetch(key)
        rescue
          _ -> {:error, :boom}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not rewrite with-rescue syntax inside quote" do
    input = ~S"""
    defmodule Sample do
      def run do
        with {:ok, value} <- {:ok, 1} do
          value
        rescue
          _ -> :error
        end
      end

      def ast do
        quote do
          with {:ok, value} <- fetch() do
            value
          rescue
            _ -> :quoted_error
          end
        end
      end
    end
    """

    expected = ~S"""
    defmodule Sample do
      def run do
        try do
          with {:ok, value} <- {:ok, 1} do
            value
          end
        rescue
          _ -> :error
        end
      end

      def ast do
        quote do
          with {:ok, value} <- fetch() do
            value
          rescue
            _ -> :quoted_error
          end
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "leaves unparseable source alone" do
    input = ~S"""
    defmodule Sample do
      def run(key) do
        with {:ok, raw} <- fetch(key
    """

    confirm_fix(fix(input), input)
  end

  test "fixed output parses and compiles" do
    input = ~S"""
    defmodule NoRescueInWithFixture do
      def run(key) do
        with {:ok, raw} <- fetch(key) do
          {:ok, raw}
        rescue
          e in ArgumentError -> {:error, Exception.message(e)}
        catch
          kind, value -> {:error, {kind, value}}
        end
      end

      defp fetch(key), do: {:ok, key}
    end
    """

    assert valid_syntax?(fix(input))
    assert compiles?(fix(input))
  end
end
