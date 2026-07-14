defmodule Credence.Semantic.FixUndefinedNestedModuleStructFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixUndefinedNestedModuleStruct

  @diag_message "AutocompleteTrie.Node.__struct__/1 is undefined (module AutocompleteTrie.Node is not available)"

  defp fix(source, message \\ @diag_message, line \\ 1) do
    FixUndefinedNestedModuleStruct.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "reorders modules so child module comes first" do
    input = ~S"""
    defmodule AutocompleteTrie do
      defstruct root: nil, size: 0

      def new() do
        %{root: %AutocompleteTrie.Node{children: %{}, weight: 0}, size: 0}
      end
    end

    defmodule AutocompleteTrie.Node do
      defstruct children: %{}, weight: 0
    end
    """

    expected = ~S"""
    defmodule AutocompleteTrie.Node do
      defstruct children: %{}, weight: 0
    end

    defmodule AutocompleteTrie do
      defstruct root: nil, size: 0

      def new() do
        %{root: %AutocompleteTrie.Node{children: %{}, weight: 0}, size: 0}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule Foo do
      defstruct bar: nil

      def new(), do: %Foo.Bar{val: 1}
    end

    defmodule Foo.Bar do
      defstruct val: 0
    end
    """

    message = "Foo.Bar.__struct__/1 is undefined (module Foo.Bar is not available)"
    assert valid_syntax?(fix(input, message))
  end

  test "returns source unchanged when child already comes first" do
    input = ~S"""
    defmodule AutocompleteTrie.Node do
      defstruct children: %{}, weight: 0
    end

    defmodule AutocompleteTrie do
      defstruct root: nil, size: 0

      def new() do
        %{root: %AutocompleteTrie.Node{children: %{}, weight: 0}, size: 0}
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged when message does not match" do
    input = """
    defmodule A do
    end

    defmodule B do
    end
    """

    confirm_fix(fix(input, "some unrelated error"), input)
  end

  test "returns source unchanged when struct not used in source" do
    input = ~S"""
    defmodule Parent do
      def hello, do: :ok
    end

    defmodule Parent.Child do
      defstruct val: 0
    end
    """

    message = "Parent.Child.__struct__/1 is undefined (module Parent.Child is not available)"
    confirm_fix(fix(input, message), input)
  end
end
