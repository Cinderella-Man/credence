defmodule Credence.Syntax.NoCaptureAsIdentityFunctionAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoCaptureAsIdentityFunction

  defp analyze(code), do: NoCaptureAsIdentityFunction.analyze(code)

  test "flags &variable used as a callback" do
    assert [%Issue{rule: :no_capture_as_identity_function, meta: %{line: 1}}] =
             analyze("Map.update!(m, :key, &new_value)")
  end

  test "reports the line of the offending &variable" do
    assert [%Issue{rule: :no_capture_as_identity_function, meta: %{line: 3}}] =
             analyze("""
             defmodule Foo do
               def bar(m, val) do
                 Map.update!(m, :key, &val)
               end
             end
             """)
  end

  test "flags multiple &variable occurrences on different lines" do
    assert [%Issue{meta: %{line: 1}}, %Issue{meta: %{line: 2}}] =
             analyze("""
             Map.update!(m, :k, &val1)
             Map.update!(m, :k2, &val2)
             """)
  end

  test "does not flag &1 (capture variable)" do
    assert analyze("Enum.filter(list, &(&1 > 0))") == []
  end

  test "does not flag &func/arity (function reference)" do
    assert analyze("Enum.map(list, &String.length/1)") == []
  end

  test "does not flag &Mod.func/arity (qualified function reference)" do
    assert analyze("Enum.map(list, &String.length/1)") == []
  end

  test "does not flag &func(&1) (capture body)" do
    assert analyze("Enum.map(list, &to_string(&1))") == []
  end

  test "does not flag the pattern inside a comment line" do
    assert analyze("# Map.update!(m, :key, &new_value)") == []
  end
end
