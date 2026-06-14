defmodule Credence.Syntax.FixMissingModuleEndAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixMissingModuleEnd

  defp analyze(code), do: FixMissingModuleEnd.analyze(code)

  test "flags a module missing its final end" do
    assert [%Issue{rule: :missing_module_end, meta: %{line: 1}}] =
             analyze("""
             defmodule Solution do
               def f(x), do: x
             """)
  end

  test "does not flag a complete module" do
    assert analyze("""
           defmodule Solution do
             def f(x), do: x
           end
           """) == []
  end

  test "does not flag a mismatched delimiter (handled by another rule)" do
    # `fn … )` — a mismatched delimiter, not a missing terminator.
    assert analyze("""
           Enum.map(list, fn x -> x + 1)
           """) == []
  end

  test "does not flag an unclosed bracket (expects ], not end)" do
    assert analyze("""
           value = [1, 2, 3
           """) == []
  end
end
