defmodule Credence.Syntax.FixScientificNotationAnalyzeTest do
  use ExUnit.Case

  alias Credence.Syntax.FixScientificNotation

  defp analyze(code) do
    FixScientificNotation.analyze(code)
  end

  describe "detects Python-style scientific notation" do
    test "1e-10" do
      assert [%{rule: :python_scientific_notation}] =
               analyze("x = 1e-10")
    end

    test "1e10 (no sign)" do
      assert [%{rule: :python_scientific_notation}] =
               analyze("x = 1e10")
    end

    test "1e+10 (positive sign)" do
      assert [%{rule: :python_scientific_notation}] =
               analyze("x = 1e+10")
    end

    test "100e3" do
      assert [%{rule: :python_scientific_notation}] =
               analyze("x = 100e3")
    end

    test "uppercase 1E-10" do
      assert [%{rule: :python_scientific_notation}] =
               analyze("x = 1E-10")
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

  describe "does NOT flag digits inside decimal-with-exponent strings" do
    test "123.456e7 in doctest" do
      assert analyze(~S'iex> Solution.float?("123.456e7")') == []
    end

    test "123.456e+7 in doctest" do
      assert analyze(~S'iex> Solution.float?("123.456e+7")') == []
    end

    test "123.456E7 in doctest" do
      assert analyze(~S'iex> Solution.float?("123.456E7")') == []
    end

    test "0.5e-10 in assert_in_delta" do
      assert analyze("assert_in_delta result, 0.5e-10, 0.001") == []
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
