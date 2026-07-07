defmodule Credence.Semantic.FixUndefinedTypeTInSpecFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixUndefinedTypeTInSpec

  @message "type t/0 is undefined (no such type in Saga)"

  defp fix(source, message, line \\ 1) do
    FixUndefinedTypeTInSpec.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "adds @type t after defstruct with keyword fields" do
    input = """
    defmodule Saga do
      defstruct steps: []

      @doc "Creates a new, empty saga struct."
      @spec new() :: t()
      def new, do: %__MODULE__{steps: []}
    end
    """

    expected = """
    defmodule Saga do
      defstruct steps: []

      @type t :: %__MODULE__{steps: list()}

      @doc "Creates a new, empty saga struct."
      @spec new() :: t()
      def new, do: %__MODULE__{steps: []}
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "adds @type t after defstruct with atom list fields" do
    input = """
    defmodule Example do
      defstruct [:name, :age]

      @spec new() :: t()
      def new, do: %__MODULE__{name: nil, age: 0}
    end
    """

    expected = """
    defmodule Example do
      defstruct [:name, :age]

      @type t :: %__MODULE__{name: list(), age: list()}

      @spec new() :: t()
      def new, do: %__MODULE__{name: nil, age: 0}
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Saga do
      defstruct steps: []

      @spec new() :: t()
      def new, do: %__MODULE__{steps: []}
    end
    """

    assert valid_syntax?(fix(input, @message))
  end

  test "returns source unchanged when no defstruct" do
    input = """
    defmodule Plain do
      @spec new() :: t()
      def new, do: :ok
    end
    """

    result = fix(input, @message)
    confirm_fix(result, input)
  end

  test "returns source unchanged when @type t already exists" do
    input = """
    defmodule Saga do
      defstruct steps: []

      @type t :: %__MODULE__{steps: list()}

      @spec new() :: t()
      def new, do: %__MODULE__{steps: []}
    end
    """

    result = fix(input, @message)
    confirm_fix(result, input)
  end

  test "returns source unchanged for unrelated error message" do
    input = """
    defmodule Example do
      defstruct [:value]

      @spec new() :: t()
      def new, do: %__MODULE__{value: nil}
    end
    """

    result = fix(input, "unrelated error")
    confirm_fix(result, input)
  end
end
