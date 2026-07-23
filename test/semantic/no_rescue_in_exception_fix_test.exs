defmodule Credence.Semantic.NoRescueInExceptionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoRescueInException

  @message "struct Exception is undefined (there is such module but it does not define a struct)"

  defp fix(source, line \\ 6) do
    NoRescueInException.fix(source, %{
      severity: :warning,
      message: @message,
      position: {line, 9}
    })
  end

  test "fixes rescue e in Exception to rescue e" do
    input = """
    defmodule Example do
      def run do
        try do
          raise "boom"
        rescue
          e in Exception ->
            {:error, e}
        end
      end
    end
    """

    expected = """
    defmodule Example do
      def run do
        try do
          raise "boom"
        rescue
          e ->
            {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes an implicit def rescue, not just try/rescue" do
    input = """
    defmodule Example do
      def run do
        raise "boom"
      rescue
        e in Exception ->
          {:error, e}
      end
    end
    """

    expected = """
    defmodule Example do
      def run do
        raise "boom"
      rescue
        e ->
          {:error, e}
      end
    end
    """

    confirm_fix(fix(input, 5), expected)
  end

  # The compiler collapses repeated occurrences inside one function into a
  # single diagnostic, and the semantic phase fixes warnings in one terminal
  # pass — so the fix must clear every clause it can see, not only the one the
  # position points at.
  test "fixes every rescue in Exception clause in one pass" do
    input = """
    defmodule Multi do
      def run do
        try do
          raise "boom"
        rescue
          e in Exception ->
            {:error, e}
        end

        try do
          raise "bang"
        rescue
          err in Exception ->
            {:error, err}
        end
      end
    end
    """

    expected = """
    defmodule Multi do
      def run do
        try do
          raise "boom"
        rescue
          e ->
            {:error, e}
        end

        try do
          raise "bang"
        rescue
          err ->
            {:error, err}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes rescue e in Elixir.Exception to rescue e" do
    input = """
    defmodule Example do
      def run(func) do
        try do
          func.()
        rescue
          e in Elixir.Exception -> {:error, {:exception, e}}
        end
      end
    end
    """

    expected = """
    defmodule Example do
      def run(func) do
        try do
          func.()
        rescue
          e -> {:error, {:exception, e}}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "leaves a sibling clause for a real struct alone" do
    input = """
    defmodule Example do
      def run do
        try do
          raise "boom"
        rescue
          e in ArgumentError ->
            {:arg, e}

          e in Exception ->
            {:error, e}
        end
      end
    end
    """

    expected = """
    defmodule Example do
      def run do
        try do
          raise "boom"
        rescue
          e in ArgumentError ->
            {:arg, e}

          e ->
            {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input, 9), expected)
  end

  test "keeps a comment attached to the rewritten clause" do
    input = """
    defmodule Example do
      def run do
        try do
          raise "boom"
        rescue
          # catch anything
          e in Exception ->
            {:error, e}
        end
      end
    end
    """

    expected = """
    defmodule Example do
      def run do
        try do
          raise "boom"
        rescue
          # catch anything
          e ->
            {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input, 7), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def run do
        try do
          raise "boom"
        rescue
          e in Exception ->
            {:error, e}
        end
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  # --- no-ops: the fix must not touch these ---

  test "returns source unchanged when the rescue is already plain" do
    input = """
    defmodule Example do
      def run do
        try do
          raise "boom"
        rescue
          e ->
            {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged when rescuing a different exception type" do
    input = """
    defmodule Example do
      def run do
        try do
          raise "boom"
        rescue
          e in ArgumentError ->
            {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged for `in Exception` used as Enum.member?/2" do
    input = """
    defmodule Example do
      def run(x) do
        if x in Exception, do: :yes, else: :no
      end
    end
    """

    confirm_fix(fix(input, 3), input)
  end

  test "returns source unchanged for a cond clause head" do
    input = """
    defmodule Example do
      def run(x) do
        cond do
          x in Exception -> :yes
          true -> :no
        end
      end
    end
    """

    confirm_fix(fix(input, 4), input)
  end

  test "returns source unchanged when the file aliases the name Exception" do
    input = """
    defmodule Example do
      def run do
        alias MyApp.Exception

        try do
          raise "boom"
        rescue
          e in Exception ->
            {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input, 8), input)
  end

  test "returns source unchanged for an `as:` alias binding Exception" do
    input = """
    defmodule Example do
      def run do
        alias MyApp.Boom, as: Exception

        try do
          raise "boom"
        rescue
          e in Exception ->
            {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input, 8), input)
  end

  test "returns source unchanged for a multi-alias binding Exception" do
    input = """
    defmodule Example do
      def run do
        alias MyApp.{Exception, Other}

        try do
          raise "boom"
        rescue
          e in Exception ->
            {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input, 8), input)
  end

  test "still fixes Elixir.Exception even when the file aliases Exception" do
    input = """
    defmodule Example do
      def run do
        alias MyApp.Exception

        try do
          raise "boom"
        rescue
          e in Elixir.Exception ->
            {:error, e}
        end
      end
    end
    """

    expected = """
    defmodule Example do
      def run do
        alias MyApp.Exception

        try do
          raise "boom"
        rescue
          e ->
            {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input, 8), expected)
  end

  test "returns source unchanged for a list of rescued types" do
    input = """
    defmodule Example do
      def run do
        try do
          raise "boom"
        rescue
          e in [Exception, ArgumentError] ->
            {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged when the source does not parse" do
    input = "defmodule Broken do"

    confirm_fix(fix(input), input)
  end
end
