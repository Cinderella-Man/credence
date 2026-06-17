defmodule Credence.Pattern.PreferSigilCharlistCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferSigilCharlist

  describe "flags single-quoted charlists" do
    test "flags 'abc'" do
      assert flagged?(PreferSigilCharlist, """
             defmodule M do
               def f, do: 'abc'
             end
             """)
    end

    test "flags each charlist in a list" do
      issues =
        check(PreferSigilCharlist, """
        defmodule M do
          def f, do: ['1', 'abc']
        end
        """)

      assert length(issues) == 2
    end
  end

  describe "does not flag" do
    test "an existing ~c sigil" do
      assert clean?(PreferSigilCharlist, """
             defmodule M do
               def f, do: ~c"abc"
             end
             """)
    end

    test "an apostrophe inside a double-quoted string" do
      assert clean?(PreferSigilCharlist, """
             defmodule M do
               def f, do: "don't change me"
             end
             """)
    end

    test "a regular double-quoted string" do
      assert clean?(PreferSigilCharlist, """
             defmodule M do
               def f, do: "abc"
             end
             """)
    end

    test "an empty charlist (rare, deliberately skipped)" do
      assert clean?(PreferSigilCharlist, """
             defmodule M do
               def f, do: ''
             end
             """)
    end
  end
end
