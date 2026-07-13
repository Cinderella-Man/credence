defmodule Credence.Semantic.NoUnusedTypeDeclarationFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoUnusedTypeDeclaration

  defp fix(source, message, line \\ 1) do
    NoUnusedTypeDeclaration.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "removes a multi-line @typep declaration" do
    input = """
    defmodule Saga do
      @typep step :: %{
        name: atom(),
        type: :compensable | :retriable,
        action_fn: function(),
        compensate_fn: function() | nil,
        max_attempts: pos_integer() | nil
      }

      defstruct steps: []

      def new, do: %Saga{steps: []}

      def add(saga, item), do: %Saga{saga | steps: [item | saga.steps]}
    end
    """

    expected = """
    defmodule Saga do
      defstruct steps: []

      def new, do: %Saga{steps: []}

      def add(saga, item), do: %Saga{saga | steps: [item | saga.steps]}
    end
    """

    confirm_fix(fix(input, "type step/0 is unused"), expected)
  end

  test "removes a single-line @typep declaration" do
    input = """
    defmodule M do
      @typep name :: atom()

      def hello, do: :world
    end
    """

    expected = """
    defmodule M do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, "type name/0 is unused"), expected)
  end

  test "leaves source unchanged when message does not match" do
    input = """
    defmodule M do
      @typep name :: atom()
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, "unrelated warning"), input)
  end

  test "removes only the type mentioned in the diagnostic" do
    input = """
    defmodule M do
      @typep name :: atom()
      @typep count :: integer()
      def hello, do: :world
    end
    """

    expected = """
    defmodule M do
      @typep name :: atom()
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, "type count/0 is unused"), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule M do
      @typep name :: atom()
      def hello, do: :world
    end
    """

    assert valid_syntax?(fix(input, "type name/0 is unused"))
  end
end
