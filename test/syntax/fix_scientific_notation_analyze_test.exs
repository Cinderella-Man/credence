defmodule Credence.Syntax.FixScientificNotationAnalyzeTest do
  use ExUnit.Case

  defp analyze(code) do
    Credence.Syntax.FixScientificNotation.analyze(code)
  end

  describe "detects Python-style scientific notation" do
    test "1e-10" do
      assert [%{rule: :python_scientific_notation}] = analyze("x = 1e-10")
    end

    test "1e10 (no sign)" do
      assert [%{rule: :python_scientific_notation}] = analyze("x = 1e10")
    end

    test "1e+10 (positive sign)" do
      assert [%{rule: :python_scientific_notation}] = analyze("x = 1e+10")
    end

    test "100e3" do
      assert [%{rule: :python_scientific_notation}] = analyze("x = 100e3")
    end

    test "uppercase 1E-10" do
      assert [%{rule: :python_scientific_notation}] = analyze("x = 1E-10")
    end

    test "inside assert_in_delta" do
      assert [%{rule: :python_scientific_notation}] =
               analyze("assert_in_delta result, 0.5, 1e-10")
    end
  end

  describe "does NOT flag valid Elixir floats" do
    test "1.0e-10" do
      assert analyze("x = 1.0e-10") == []
    end

    test "1.5e10" do
      assert analyze("x = 1.5e10") == []
    end

    test "2.0e+3" do
      assert analyze("x = 2.0e+3") == []
    end
  end

  describe "does NOT flag non-numeric uses" do
    test "comment containing 1e10" do
      assert analyze("# tolerance is 1e-10") == []
    end

    test "plain integer" do
      assert analyze("x = 100") == []
    end

    test "plain float" do
      assert analyze("x = 1.5") == []
    end
  end
end
