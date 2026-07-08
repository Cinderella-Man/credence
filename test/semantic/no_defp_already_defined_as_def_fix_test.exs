defmodule Credence.Semantic.NoDefpAlreadyDefinedAsDefFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoDefpAlreadyDefinedAsDef

  @real_message "defp sequence/2 already defined as def"

  defp fix(source, message, line \\ 1) do
    NoDefpAlreadyDefinedAsDef.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "removes defp clause when def with same name/arity exists" do
    input = """
    defmodule Example do
      def sequence(name, formatter_fn) do
        formatter_fn.(name)
      end

      # ... other code ...

      defp sequence(name, formatter_fn) when is_function(formatter_fn, 1) do
        formatter_fn.(name + 1)
      end
    end
    """

    expected = """
    defmodule Example do
      def sequence(name, formatter_fn) do
        formatter_fn.(name)
      end

      # ... other code ...
    end
    """

    confirm_fix(fix(input, @real_message, 8), expected)
  end

  test "removes defp without guard clause" do
    input = """
    defmodule Example do
      def greet(name) do
        "Hello, " <> name
      end

      defp greet(name) do
        "Hi, " <> name
      end
    end
    """

    expected = """
    defmodule Example do
      def greet(name) do
        "Hello, " <> name
      end
    end
    """

    confirm_fix(fix(input, "defp greet/1 already defined as def", 6), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def sequence(name, formatter_fn) do
        formatter_fn.(name)
      end

      defp sequence(name, formatter_fn) when is_function(formatter_fn, 1) do
        formatter_fn.(name + 1)
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message, 6))
  end

  test "returns source unchanged when no matching defp found" do
    input = """
    defmodule Example do
      def other(name) do
        name
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule Example do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
