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

  test "leaves nested-module duplicates untouched (only top-level module handled)" do
    input = ~S"""
    defmodule Outer do
      defmodule Inner do
        defstruct [:a]
        defstruct [:a, :b]
      end
    end
    """

    confirm_fix(fix(input), input)
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
