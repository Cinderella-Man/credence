defmodule Credence.Syntax.FixScientificNotationFixTest do
  use ExUnit.Case

  alias Credence.Syntax.FixScientificNotation

  defp fix(code) do
    FixScientificNotation.fix(code)
  end

  describe "fixes bare integer scientific notation" do
    test "1e-10 → 1.0e-10" do
      assert fix("x = 1e-10") == "x = 1.0e-10"
    end

    test "1e10 → 1.0e10" do
      assert fix("x = 1e10") == "x = 1.0e10"
    end

    test "1e+10 → 1.0e+10" do
      assert fix("x = 1e+10") == "x = 1.0e+10"
    end

    test "100e3 → 100.0e3" do
      assert fix("x = 100e3") == "x = 100.0e3"
    end

    test "5e-3 → 5.0e-3" do
      assert fix("x = 5e-3") == "x = 5.0e-3"
    end

    test "uppercase E normalized to lowercase" do
      assert fix("x = 1E-10") == "x = 1.0e-10"
    end

    test "inside assert_in_delta" do
      assert fix("assert_in_delta result, 0.5, 1e-10") ==
               "assert_in_delta result, 0.5, 1.0e-10"
    end

    test "multiple on same line" do
      assert fix("assert_in_delta a, 1e-5, 1e-10") ==
               "assert_in_delta a, 1.0e-5, 1.0e-10"
    end
  end

  describe "leaves valid notation unchanged" do
    test "1.0e-10" do
      assert fix("x = 1.0e-10") == "x = 1.0e-10"
    end

    test "1.5e10" do
      assert fix("x = 1.5e10") == "x = 1.5e10"
    end

    test "2.0e+3" do
      assert fix("x = 2.0e+3") == "x = 2.0e+3"
    end
  end

  describe "leaves non-numeric content unchanged" do
    test "comments" do
      code = "# tolerance is 1e-10"
      assert fix(code) == code
    end

    test "plain integers" do
      code = "x = 100"
      assert fix(code) == code
    end

    test "regular code" do
      code = "Enum.map(list, &to_string/1)"
      assert fix(code) == code
    end
  end
end
