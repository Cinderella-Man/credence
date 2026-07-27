defmodule Credence.Syntax.FixMixedRequiredOptionalMapKeysFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixMixedRequiredOptionalMapKeys

  defp analyze(code), do: FixMixedRequiredOptionalMapKeys.analyze(code)
  defp fix(code), do: FixMixedRequiredOptionalMapKeys.fix(code)

  test "fixes mixed required and optional map keys in typespec" do
    input = ~S"""
    defmodule M do
      @type record :: %{state: atom(), optional(atom()) => any()}
    end
    """

    expected = ~S"""
    defmodule M do
      @type record :: %{optional(atom()) => any()}
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes multiple required keys before optional" do
    input = ~S'%{a: atom(), b: integer(), optional(atom()) => any()}'
    expected = ~S'%{optional(atom()) => any()}'

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = ~S"""
    defmodule M do
      @type record :: %{state: atom(), optional(atom()) => any()}
    end
    """

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule M do
      @type record :: %{state: atom(), optional(atom()) => any()}
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "fix does not mangle valid optional-only map" do
    input = ~S'%{optional(atom()) => any()}'
    confirm_fix(fix(input), input)
  end

  test "fix does not mangle valid required-key-only map" do
    input = ~S'%{state: atom(), name: String.t()}'
    confirm_fix(fix(input), input)
  end
end
