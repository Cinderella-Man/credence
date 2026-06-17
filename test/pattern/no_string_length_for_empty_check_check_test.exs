defmodule Credence.Pattern.NoStringLengthForEmptyCheckCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoStringLengthForEmptyCheck

  describe "flags String.length(<binary>) == 0 / != 0" do
    test "String.* call argument" do
      assert flagged?(NoStringLengthForEmptyCheck, """
             defmodule M do
               def f(line), do: String.length(String.trim(line)) == 0
             end
             """)
    end

    test "flipped operand order" do
      assert flagged?(NoStringLengthForEmptyCheck, """
             defmodule M do
               def f(x), do: 0 == String.length(String.downcase(x))
             end
             """)
    end

    test "<> concatenation, != 0" do
      assert flagged?(NoStringLengthForEmptyCheck, """
             defmodule M do
               def f(a, b), do: String.length(a <> b) != 0
             end
             """)
    end

    test "string literal" do
      assert flagged?(NoStringLengthForEmptyCheck, """
             defmodule M do
               def f, do: String.length("foo") == 0
             end
             """)
    end
  end

  describe "does not flag (unsafe / out of scope)" do
    test "bare variable argument (might not be a string)" do
      assert clean?(NoStringLengthForEmptyCheck, """
             defmodule M do
               def f(s), do: String.length(s) == 0
             end
             """)
    end

    test "list-returning argument" do
      assert clean?(NoStringLengthForEmptyCheck, """
             defmodule M do
               def f(s), do: String.length(String.split(s)) == 0
             end
             """)
    end

    test "comparison against a non-zero value" do
      assert clean?(NoStringLengthForEmptyCheck, """
             defmodule M do
               def f(s), do: String.length(String.trim(s)) == 1
             end
             """)
    end

    test "non-binary bitstring literal (String.length raises, but == \"\" returns false)" do
      assert clean?(NoStringLengthForEmptyCheck, """
             defmodule M do
               def f, do: String.length(<<1::1>>) == 0
             end
             """)
    end
  end
end
