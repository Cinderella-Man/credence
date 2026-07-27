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

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule DuplicateDefstruct do
      defstruct [:a]
      defstruct [:a, :b]
    end
    """

    assert valid_syntax?(fix(input))
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
