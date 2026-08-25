defmodule Credence.Semantic.NoDuplicateDefstructFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoDuplicateDefstruct

  @match_msg "defstruct has already been called for RetrySaga, defstruct can only be called once per module"

  defp fix(source, message \\ @match_msg, line \\ 1) do
    NoDuplicateDefstruct.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  test "removes duplicate defstruct, keeping the last" do
    input = ~S"""
    defmodule DuplicateDefstruct do
      @moduledoc false
      defstruct [:a]
      defstruct [:a, :b, c: nil]
      def hello, do: :ok
    end
    """

    expected = ~S"""
    defmodule DuplicateDefstruct do
      @moduledoc false
      defstruct [:a, :b, c: nil]
      def hello, do: :ok
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed and keeps only the last defstruct" do
    input = ~S"""
    defmodule DuplicateDefstruct do
      defstruct [:a]
      defstruct [:a, :b]
    end
    """

    expected = ~S"""
    defmodule DuplicateDefstruct do
      defstruct [:a, :b]
    end
    """

    assert valid_syntax?(fix(input))
    confirm_fix(fix(input), expected)
  end

  test "collapses three defstructs to the last one" do
    input = ~S"""
    defmodule Foo do
      defstruct [:a]
      defstruct name: nil
      defstruct name: nil, age: 0
    end
    """

    expected = ~S"""
    defmodule Foo do
      defstruct name: nil, age: 0
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "removes duplicate defstruct inside a nested module" do
    input = ~S"""
    defmodule Outer do
      defmodule Inner do
        defstruct [:a]
        defstruct [:a, :b]
      end
    end
    """

    expected = ~S"""
    defmodule Outer do
      defmodule Inner do
        defstruct [:a, :b]
      end
    end
    """

    fixed = fix(input)

    confirm_fix(fixed, expected)
    assert {:ok, _diagnostics} = Credence.RuleHelpers.compile_and_capture(fixed)
    assert {:ok, _diagnostics} = Credence.RuleHelpers.compile_and_capture(expected)
  end

  test "removes duplicate defstruct inside a conditional block" do
    input = ~S"""
    defmodule ConditionalDefstruct do
      if true do
        defstruct [:a]
        defstruct [:a, :b]
      end
    end
    """

    expected = ~S"""
    defmodule ConditionalDefstruct do
      if true do
        defstruct [:a, :b]
      end
    end
    """

    fixed = fix(input)

    confirm_fix(fixed, expected)
    assert {:ok, _diagnostics} = Credence.RuleHelpers.compile_and_capture(fixed)
    assert {:ok, _diagnostics} = Credence.RuleHelpers.compile_and_capture(expected)
  end

  test "removes duplicate defstruct from a module in a multi-module file" do
    input = ~S"""
    defmodule FirstDefstruct do
      defstruct [:a]
      defstruct [:a, :b]
    end

    defmodule SecondDefstruct do
      def value, do: :ok
    end
    """

    expected = ~S"""
    defmodule FirstDefstruct do
      defstruct [:a, :b]
    end

    defmodule SecondDefstruct do
      def value, do: :ok
    end
    """

    fixed = fix(input)

    confirm_fix(fixed, expected)
    assert {:ok, _diagnostics} = Credence.RuleHelpers.compile_and_capture(fixed)
    assert {:ok, _diagnostics} = Credence.RuleHelpers.compile_and_capture(expected)
  end

  test "returns source unchanged when no duplicates" do
    input = ~S"""
    defmodule Good do
      defstruct [:a, :b, c: nil]
      def hello, do: :ok
    end
    """

    confirm_fix(fix(input), input)
  end
end
