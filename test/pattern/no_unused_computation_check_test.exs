defmodule Credence.Pattern.NoUnusedComputationCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoUnusedComputation, as: Rule

  describe "flags a dead total-call on a provably-typed argument" do
    test "length on a variable bound to a list-returning call" do
      assert flagged?(Rule, """
             def f(s) do
               chars = String.graphemes(s)
               _n = length(chars)
               Enum.with_index(chars)
             end
             """)
    end

    test "length on a list literal" do
      assert flagged?(Rule, """
             def f do
               _n = length([1, 2, 3])
               :ok
             end
             """)
    end

    test "Enum.count on a variable bound to Enum.map" do
      assert flagged?(Rule, """
             def f(xs) do
               nums = Enum.map(xs, &double/1)
               _c = Enum.count(nums)
               nums
             end
             """)
    end
  end

  describe "does NOT flag (unsafe — could drop a crash)" do
    test "length on a bare variable of unknown type" do
      assert clean?(Rule, """
             def f(x) do
               _n = length(x)
               :ok
             end
             """)
    end

    test "String.length on a bare variable" do
      assert clean?(Rule, """
             def f(name) do
               _n = String.length(name)
               :ok
             end
             """)
    end

    test "a partial function (div) even on numbers" do
      assert clean?(Rule, """
             def f(a) do
               _n = div(a, 2)
               :ok
             end
             """)
    end

    test "hd is partial (raises on []) — never removed" do
      assert clean?(Rule, """
             def f do
               _h = hd([1, 2, 3])
               :ok
             end
             """)
    end

    test "the dead computation is the block's last expression" do
      assert clean?(Rule, """
             def f do
               :ok
               _n = length([1, 2, 3])
             end
             """)
    end

    test "an underscore-prefixed binding that is read later" do
      assert clean?(Rule, """
             def f do
               _n = length([1])
               _n
             end
             """)
    end
  end
end
