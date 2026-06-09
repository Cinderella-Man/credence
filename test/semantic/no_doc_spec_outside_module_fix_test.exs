defmodule Credence.Semantic.NoDocSpecOutsideModuleFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Semantic.NoDocSpecOutsideModule

  defp fix(source, message, line \\ 1) do
    NoDocSpecOutsideModule.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes the source by wrapping in defmodule" do
    input = """
    @doc "Squares a number."
    @spec square(integer()) :: integer()
    def square(x), do: x * x
    """

    expected = """
    defmodule Solution do
      @doc "Squares a number."
      @spec square(integer()) :: integer()
      def square(x), do: x * x
    end
    """

    message = "module attribute @doc was set outside module"
    assert fix(input, message) == expected
  end

  test "fixes a source with only @spec and def" do
    input = """
    @spec add(integer(), integer()) :: integer()
    def add(a, b), do: a + b
    """

    expected = """
    defmodule Solution do
      @spec add(integer(), integer()) :: integer()
      def add(a, b), do: a + b
    end
    """

    message = "module attribute @spec was set outside module"
    assert fix(input, message) == expected
  end

  test "fixed output is well-formed (parses)" do
    message = "module attribute @doc was set outside module"

    assert valid_syntax?(
             fix(
               """
               @spec foo(integer()) :: integer()
               def foo(x), do: x + 1
               """,
               message
             )
           )
  end

  test "preserves inner indentation after wrapping" do
    input = """
    @doc "Greets someone."
    @spec greet(String.t()) :: String.t()
    def greet(name) do
      "Hello, " <> name <> "!"
    end
    """

    expected = """
    defmodule Solution do
      @doc "Greets someone."
      @spec greet(String.t()) :: String.t()
      def greet(name) do
        "Hello, " <> name <> "!"
      end
    end
    """

    message = "module attribute @doc was set outside module"
    assert fix(input, message) == expected
  end
end