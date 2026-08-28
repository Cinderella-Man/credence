defmodule Credence.Pattern.NoUnusedUnderscoreAssignmentCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoUnusedUnderscoreAssignment, as: Rule

  describe "flags a dead underscore assignment with a pure RHS" do
    test "bare variable RHS, not last expression" do
      assert flagged?(Rule, """
             def process(list) do
               _length = list
               n = length(list)
               if n < 3, do: 0, else: n
             end
             """)
    end

    test "literal RHS" do
      assert flagged?(Rule, """
             def run(x) do
               _unused = 1
               x + 1
             end
             """)
    end

    test "atom literal RHS" do
      assert flagged?(Rule, """
             def run(x) do
               _ignored = :ok
               x
             end
             """)
    end
  end

  describe "does not flag (outside the safe core)" do
    test "RHS is a function call (not provably pure)" do
      assert clean?(Rule, """
             def run(x) do
               _unused = IO.puts("hi")
               x
             end
             """)
    end

    test "RHS is an operator expression" do
      assert clean?(Rule, """
             def run(x) do
               _unused = x + 1
               x
             end
             """)
    end

    test "variable is referenced later" do
      assert clean?(Rule, """
             def run(x) do
               _kept = x
               _kept + 1
             end
             """)
    end

    test "assignment is the last expression (the block's value)" do
      assert clean?(Rule, """
             def run(x) do
               x + 1
               _unused = 0
             end
             """)
    end

    test "non-underscore variable is left to other rules" do
      assert clean?(Rule, """
             def run(x) do
               unused = 1
               x
             end
             """)
    end

    test "destructuring left side is never touched" do
      assert clean?(Rule, """
             def run(pair) do
               {_a, _b} = pair
               :ok
             end
             """)
    end

    test "special forms whose names begin with underscores are never touched" do
      assert clean?(Rule, """
             defmodule NoUnusedUnderscoreAssignmentCheckSpecialFormFixture do
               def run do
                 __MODULE__ = :ok
                 :done
               end
             end
             """)
    end
  end
end
