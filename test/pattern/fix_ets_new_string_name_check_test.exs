defmodule Credence.Pattern.FixEtsNewStringNameCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.FixEtsNewStringName

  describe "flags" do
    test "a literal string table name" do
      assert [%Issue{rule: :fix_ets_new_string_name}] =
               check(FixEtsNewStringName, """
               defmodule EtsCheckA do
                 def start, do: :ets.new("cache", [:set])
               end
               """)
    end

    test "with any option list" do
      assert flagged?(FixEtsNewStringName, """
             defmodule EtsCheckB do
               def start, do: :ets.new("my_cache", [:set, :named_table, {:keypos, 2}])
             end
             """)
    end

    test "the message names the atom to use" do
      [issue] =
        check(FixEtsNewStringName, """
        defmodule EtsCheckC do
          def start, do: :ets.new("cache", [:set])
        end
        """)

      assert String.contains?(issue.message, ":cache")
    end
  end

  describe "leaves alone" do
    test "an atom name, which is already correct" do
      assert clean?(FixEtsNewStringName, """
             defmodule EtsCheckD do
               def start, do: :ets.new(:cache, [:set])
             end
             """)
    end

    test "a name that is not a literal" do
      assert clean?(FixEtsNewStringName, """
             defmodule EtsCheckE do
               def start(name), do: :ets.new(name, [:set])
             end
             """)
    end

    # `check/2` and `fix_patches/2` share `valid_atom_name?/1` so they cannot
    # disagree. Reporting this would produce a `:no_op` — a finding raised and
    # left unfixed, the shape "fix or drop it" exists to prevent.
    test "a string that cannot be written as a bare atom" do
      assert clean?(FixEtsNewStringName, """
             defmodule EtsCheckF do
               def start, do: :ets.new("my table", [:set])
             end
             """)
    end

    test "an empty string name" do
      assert clean?(FixEtsNewStringName, """
             defmodule EtsCheckG do
               def start, do: :ets.new("", [:set])
             end
             """)
    end

    # The near miss: a different :ets function whose first argument is legitimately
    # not an atom.
    test "a string argument to another :ets function" do
      assert clean?(FixEtsNewStringName, """
             defmodule EtsCheckH do
               def get(table), do: :ets.lookup(table, "key")
             end
             """)
    end

    test "a same-named function on another module" do
      assert clean?(FixEtsNewStringName, """
             defmodule EtsCheckI do
               def start, do: MyTables.new("cache", [:set])
             end
             """)
    end
  end
end
