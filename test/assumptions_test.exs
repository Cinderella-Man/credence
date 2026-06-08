defmodule Credence.AssumptionsTest do
  use ExUnit.Case, async: true

  alias Credence.Assumptions
  alias Credence.RuleHelpers

  describe "registry" do
    test "defaults/0 has the expected shape and single_codepoint_graphemes is on" do
      defaults = Assumptions.defaults()

      assert is_map(defaults)
      assert defaults[:single_codepoint_graphemes] == true
      assert Map.keys(defaults) == Assumptions.names()
    end

    test "names/0 lists known switches; known?/1 reflects it" do
      assert :single_codepoint_graphemes in Assumptions.names()
      assert Assumptions.known?(:single_codepoint_graphemes)
      refute Assumptions.known?(:not_a_real_switch)
    end

    test "validate!/1 returns the map for known names" do
      map = %{single_codepoint_graphemes: false}
      assert Assumptions.validate!(map) == map
    end

    test "validate!/1 raises a clear error on an unknown name" do
      assert_raise ArgumentError, ~r/unknown assumption.*:nope/s, fn ->
        Assumptions.validate!(%{nope: true})
      end
    end
  end

  describe "merge_assumptions/2 algebra (registry-independent, two switches)" do
    @defaults %{a: true, b: true}

    test "no layers → defaults unchanged" do
      assert RuleHelpers.merge_assumptions(@defaults, []) == %{a: true, b: true}
    end

    test "a small map patches only its named keys" do
      assert RuleHelpers.merge_assumptions(@defaults, [%{b: false}]) == %{a: true, b: false}
    end

    test "an empty map is a no-op (missing place does nothing)" do
      assert RuleHelpers.merge_assumptions(@defaults, [%{}]) == @defaults
    end

    test "later layer wins; unmentioned keys fall through" do
      assert RuleHelpers.merge_assumptions(@defaults, [%{b: false}, %{a: false}]) ==
               %{a: false, b: false}

      # call patches only :a; :b keeps the config layer's value, NOT the default
      assert RuleHelpers.merge_assumptions(@defaults, [%{b: false}, %{}]) ==
               %{a: true, b: false}
    end

    test ":strict forces every key off; :default resets every key" do
      assert RuleHelpers.merge_assumptions(@defaults, [:strict]) == %{a: false, b: false}
      assert RuleHelpers.merge_assumptions(@defaults, [:strict, :default]) == %{a: true, b: true}
    end

    test "a small map over :strict re-enables only the named switch" do
      assert RuleHelpers.merge_assumptions(@defaults, [:strict, %{a: true}]) ==
               %{a: true, b: false}
    end
  end

  describe "effective_assumptions/1 (real registry, three places)" do
    test "default: single_codepoint_graphemes is on" do
      assert RuleHelpers.effective_assumptions([])[:single_codepoint_graphemes] == true
    end

    test ":strict turns it off" do
      assert RuleHelpers.effective_assumptions(assumptions: :strict)[:single_codepoint_graphemes] ==
               false
    end

    test "config is respected and call options override it" do
      Application.put_env(:credence, :assumptions, :strict)
      on_exit(fn -> Application.delete_env(:credence, :assumptions) end)

      # config alone → off
      assert RuleHelpers.effective_assumptions([])[:single_codepoint_graphemes] == false

      # call re-enables that one switch for this run
      effective =
        RuleHelpers.effective_assumptions(assumptions: %{single_codepoint_graphemes: true})

      assert effective[:single_codepoint_graphemes] == true
    end

    test "a missing config place does nothing" do
      Application.delete_env(:credence, :assumptions)
      assert RuleHelpers.effective_assumptions([])[:single_codepoint_graphemes] == true
    end

    test "an unknown switch name you pass raises" do
      assert_raise ArgumentError, ~r/unknown assumption/, fn ->
        RuleHelpers.effective_assumptions(assumptions: %{bogus: true})
      end
    end

    test "an invalid assumptions value raises" do
      assert_raise ArgumentError, ~r/invalid `:assumptions` value/, fn ->
        RuleHelpers.effective_assumptions(assumptions: :stict)
      end
    end
  end
end
