defmodule Credence.Pattern.FixEtsOptionsBareKeyposCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.FixEtsOptionsBareKeypos

  describe "flags" do
    test "a flattened :keypos pair" do
      assert [%Issue{rule: :fix_ets_options_bare_keypos}] =
               check(FixEtsOptionsBareKeypos, """
               defmodule KpCheckA do
                 def start, do: :ets.new(:records, [:set, :keypos, 2])
               end
               """)
    end

    test "wherever it sits in the option list" do
      assert flagged?(FixEtsOptionsBareKeypos, """
             defmodule KpCheckB do
               def start, do: :ets.new(:records, [:named_table, :set, :keypos, 3])
             end
             """)
    end
  end

  describe "leaves alone" do
    test "an already-tupled :keypos" do
      assert clean?(FixEtsOptionsBareKeypos, """
             defmodule KpCheckC do
               def start, do: :ets.new(:records, [:set, {:keypos, 2}])
             end
             """)
    end

    test "an option list with no :keypos at all" do
      assert clean?(FixEtsOptionsBareKeypos, """
             defmodule KpCheckD do
               def start, do: :ets.new(:records, [:set, :named_table])
             end
             """)
    end

    # The position must be a literal integer. A variable could hold anything,
    # and pairing it would be a guess about what the author meant.
    test "a :keypos followed by a variable" do
      assert clean?(FixEtsOptionsBareKeypos, """
             defmodule KpCheckE do
               def start(n), do: :ets.new(:records, [:set, :keypos, n])
             end
             """)
    end

    # `:keypos` as the last element has nothing after it to pair with — a
    # different mistake, and not one this rule can repair.
    test "a trailing :keypos with nothing after it" do
      assert clean?(FixEtsOptionsBareKeypos, """
             defmodule KpCheckF do
               def start, do: :ets.new(:records, [:set, :keypos])
             end
             """)
    end

    test "a same-shaped list passed to something other than :ets.new" do
      assert clean?(FixEtsOptionsBareKeypos, """
             defmodule KpCheckG do
               def start, do: MyTables.new(:records, [:set, :keypos, 2])
             end
             """)
    end
  end
end
