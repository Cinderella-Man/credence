defmodule Credence.Semantic.NoHallucinatedDefpstructFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedDefpstruct

  @message "undefined function defpstruct/2 (there is no such import)"

  defp fix(source, message, line \\ 1) do
    NoHallucinatedDefpstruct.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces defpstruct with defstruct and @type, rewrites %Node{} to %__MODULE__{}" do
    input = ~S"""
    defmodule FixTest do
      defpstruct Node do
        @type t :: %__MODULE__{
                key: {integer, integer},
                max_finish: integer,
                left: t | nil,
                right: t | nil,
                height: integer,
                count: integer
              }
        defstruct [:key, :max_finish, :left, :right, :height, :count]
      end

      def new, do: %Node{key: {1, 2}, max_finish: 2, left: nil, right: nil, height: 1, count: 1}
    end
    """

    expected = ~S"""
    defmodule FixTest do
      defstruct [:key, :max_finish, :left, :right, :height, :count]

      @type t :: %__MODULE__{
              key: {integer, integer},
              max_finish: integer,
              left: t | nil,
              right: t | nil,
              height: integer,
              count: integer
            }

      def new, do: %__MODULE__{key: {1, 2}, max_finish: 2, left: nil, right: nil, height: 1, count: 1}
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule FixTest do
      defpstruct Node do
        @type t :: %__MODULE__{
                key: {integer, integer},
                max_finish: integer,
                left: t | nil,
                right: t | nil,
                height: integer,
                count: integer
              }
        defstruct [:key, :max_finish, :left, :right, :height, :count]
      end

      def new, do: %Node{key: {1, 2}, max_finish: 2, left: nil, right: nil, height: 1, count: 1}
    end
    """

    assert valid_syntax?(fix(input, @message))
  end

  test "returns source unchanged when no defpstruct pattern" do
    input = ~S"""
    defmodule Factory do
      defstruct [:name, :email]

      def build do
        %__MODULE__{name: "test", email: "test@example.com"}
      end
    end
    """

    result = fix(input, @message)
    confirm_fix(result, input)
  end

  test "returns source unchanged for unrelated error message" do
    input = ~S"""
    defmodule Example do
      def test do
        x + 1
      end
    end
    """

    result = fix(input, "unrelated error")
    confirm_fix(result, input)
  end

  test "rewrites multiple %Node{} references" do
    input = ~S"""
    defmodule FixTest do
      defpstruct Node do
        defstruct [:key, :value]
      end

      def new(key, value), do: %Node{key: key, value: value}
      def update(node, value), do: %Node{key: node.key, value: value}
    end
    """

    expected = ~S"""
    defmodule FixTest do
      defstruct [:key, :value]

      def new(key, value), do: %__MODULE__{key: key, value: value}
      def update(node, value), do: %__MODULE__{key: node.key, value: value}
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "defpstruct without @type" do
    input = ~S"""
    defmodule FixTest do
      defpstruct Node do
        defstruct [:key, :value]
      end

      def new, do: %Node{key: 1, value: 2}
    end
    """

    expected = ~S"""
    defmodule FixTest do
      defstruct [:key, :value]

      def new, do: %__MODULE__{key: 1, value: 2}
    end
    """

    confirm_fix(fix(input, @message), expected)
  end
end
