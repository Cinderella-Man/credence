defmodule Credence.Semantic.NoMessageAccessOnRescueVariableFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoMessageAccessOnRescueVariable

  @real_message "unknown key .message in expression"

  defp fix(source, message, line) do
    NoMessageAccessOnRescueVariable.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "only rewrites the bare-rescue var, not a real .message field elsewhere" do
    input = """
    defmodule M do
      defmodule Widget do
        defstruct [:message]
      end

      def show(%Widget{} = w), do: w.message

      def run do
        try do
          :ok
        rescue
          e -> {w().message, e.message}
        end
      end
    end
    """

    expected = """
    defmodule M do
      defmodule Widget do
        defstruct [:message]
      end

      def show(%Widget{} = w), do: w.message

      def run do
        try do
          :ok
        rescue
          e -> {w().message, Exception.message(e)}
        end
      end
    end
    """

    confirm_fix(fix(input, @real_message, 13), expected)
  end

  test "rewrites every .message use of the rescue var" do
    input = """
    try do
      :ok
    rescue
      e -> {e.message, e.message}
    end
    """

    expected = """
    try do
      :ok
    rescue
      e -> {Exception.message(e), Exception.message(e)}
    end
    """

    confirm_fix(fix(input, @real_message, 4), expected)
  end

  test "leaves a typed rescue (e in RuntimeError) untouched" do
    input = """
    try do
      :ok
    rescue
      e in RuntimeError -> e.message
    end
    """

    confirm_fix(fix(input, @real_message, 4), input)
  end

  test "leaves the clause untouched when the rescue var is rebound in the body" do
    input = """
    try do
      :ok
    rescue
      e ->
        e = normalize(e)
        e.message
    end
    """

    confirm_fix(fix(input, @real_message, 6), input)
  end

  test "replaces e.message with Exception.message(e)" do
    input = """
    defmodule Simple do
      def run do
        try do
          :ok
        rescue
          e -> {:error, e.message}
        end
      end
    end
    """

    expected = """
    defmodule Simple do
      def run do
        try do
          :ok
        rescue
          e -> {:error, Exception.message(e)}
        end
      end
    end
    """

    confirm_fix(fix(input, @real_message, 6), expected)
  end

  test "replaces e.message in nested rescue" do
    input = """
    defmodule MetricAggregator do
      def summarize(path) do
        with {:ok, file} <- File.open(path, [:read]) do
          try do
            result = %{total: 1}
            File.close(file)
            {:ok, result}
          rescue
            e -> {:error, e.message}
          end
        end
      end
    end
    """

    expected = """
    defmodule MetricAggregator do
      def summarize(path) do
        with {:ok, file} <- File.open(path, [:read]) do
          try do
            result = %{total: 1}
            File.close(file)
            {:ok, result}
          rescue
            e -> {:error, Exception.message(e)}
          end
        end
      end
    end
    """

    confirm_fix(fix(input, @real_message, 9), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule ParseCheck do
      def run do
        try do
          :ok
        rescue
          e -> {:error, e.message}
        end
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message, 6))
  end

  test "returns source unchanged when no .message access present" do
    input = """
    defmodule Clean do
      def run do
        try do
          :ok
        rescue
          e -> {:error, Exception.message(e)}
        end
      end
    end
    """

    confirm_fix(fix(input, @real_message, 6), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule Unrelated do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message, 1), input)
  end
end
