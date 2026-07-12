defmodule Credence.Syntax.FixMixedRequiredOptionalMapKeysAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixMixedRequiredOptionalMapKeys

  defp analyze(code), do: FixMixedRequiredOptionalMapKeys.analyze(code)

  test "flags mixed required and optional map keys in typespec" do
    input = ~S"""
    defmodule M do
      @type record :: %{state: atom(), optional(atom()) => any()}
    end
    """

    assert [%Issue{rule: :fix_mixed_required_optional_map_keys}] = analyze(input)
  end

  test "flags multiple required keys before optional" do
    assert [%Issue{rule: :fix_mixed_required_optional_map_keys}] =
             analyze(~S'%{a: atom(), b: integer(), optional(atom()) => any()}')
  end

  test "leaves valid optional-only map alone" do
    assert analyze(~S'%{optional(atom()) => any()}') == []
  end

  test "leaves valid required-key-only map alone" do
    assert analyze(~S'%{state: atom(), name: String.t()}') == []
  end

  test "leaves valid arrow-only map alone" do
    assert analyze(~S'%{atom() => any()}') == []
  end

  test "leaves valid non-map code alone" do
    assert analyze(~S'foo(bar)') == []
  end
end
