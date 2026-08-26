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

  test "semantic dispatch repairs the compiler's bare-rescue diagnostic" do
    input = """
    defmodule NMAORVSemanticDispatch do
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
    defmodule NMAORVSemanticDispatch do
      def run do
        try do
          :ok
        rescue
          e -> {:error, Map.fetch!(e, :message)}
        end
      end
    end
    """

    assert {:ok, [diagnostic]} = Credence.RuleHelpers.compile_and_capture(input)
    assert NoMessageAccessOnRescueVariable.match?(diagnostic)

    emitted = Credence.Semantic.fix(input)

    confirm_fix(emitted, expected)
    assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(emitted)
    assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(expected)
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
          e -> {w().message, Map.fetch!(e, :message)}
        end
      end
    end
    """

    confirm_fix(fix(input, @real_message, 12), expected)
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
      e -> {Map.fetch!(e, :message), Map.fetch!(e, :message)}
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

  test "replaces e.message with Map.fetch!(e, :message)" do
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
          e -> {:error, Map.fetch!(e, :message)}
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
            e -> {:error, Map.fetch!(e, :message)}
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

  test "preserves direct message-field semantics for custom exceptions" do
    input = """
    defmodule NMAORVCustomMessageError do
      defexception [:message]
      def message(_exception), do: "callback message"
    end

    defmodule NMAORVCustomMessageProbe do
      def run do
        try do
          raise NMAORVCustomMessageError, message: "stored message"
        rescue
          e -> e.message
        end
      end
    end

    unless NMAORVCustomMessageProbe.run() == "stored message", do: raise("meaning changed")
    """

    expected = String.replace(input, "e -> e.message", "e -> Map.fetch!(e, :message)")
    emitted = fix(input, @real_message, 11)

    confirm_fix(emitted, expected)
    assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(emitted)
  end

  test "rewrites the flagged access before a later rebinding" do
    input = """
    defmodule NMAORVLaterRebinding do
      def run do
        try do
          raise "original"
        rescue
          e ->
            value = e.message
            e = RuntimeError.exception("normalized")
            {value, e}
        end
      end
    end
    """

    expected = String.replace(input, "value = e.message", "value = Map.fetch!(e, :message)")
    emitted = fix(input, @real_message, 7)

    confirm_fix(emitted, expected)
    assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(emitted)
  end

  test "uses the diagnostic position and leaves quoted rescue code unchanged" do
    input = """
    defmodule NMAORVQuotedRescue do
      def quoted do
        quote do
          try do
            :ok
          rescue
            e -> e.message
          end
        end
      end

      def run do
        try do
          raise "real warning"
        rescue
          e -> e.message
        end
      end
    end
    """

    expected =
      String.replace(
        input,
        "      e -> e.message\n    end\n  end\nend",
        "      e -> Map.fetch!(e, :message)\n    end\n  end\nend"
      )

    confirm_fix(fix(input, @real_message, 16), expected)
  end
end
