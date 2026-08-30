defmodule Credence.EquivalenceInputsTest do
  use ExUnit.Case, async: true

  alias Credence.EquivalenceInputs, as: E

  # C2.1. A battery dimension earns its place by DISCRIMINATING — by containing
  # at least one input on which the divergence it is named for is observable.
  # A dimension that cannot tell two implementations apart is decoration, and
  # the equivalence harness reports EQUIVALENT for free.
  #
  # docs/14 E1 is why this file exists: `term_lists`' only mixed-kind entry tied
  # at the MINIMUM, so first-vs-last-maximal divergences were invisible and two
  # live bugs shipped through a green equivalence suite. Each test below pins
  # the divergence its dimension is supposed to witness, against the actual
  # inputs, so the same hole cannot open silently in the new dimensions.

  describe "maps" do
    test "the key-identity trap predicate rejects an unrelated second key" do
      decoy = %{1 => :int, other: :value}

      refute key_identity_trap?(decoy)
    end

    test "contains a key-identity trap: `==` keys that are distinct as map keys" do
      trap = Enum.find(E.maps(), &key_identity_trap?/1)

      assert trap, "no map with both 1 and 1.0 as keys — the key-identity trap is missing"
      assert map_size(trap) == 2, "1 and 1.0 must be DISTINCT map keys"
      [int, float] = [Enum.at([1], 0), Enum.at([1.0], 0)]
      assert int == float, "premise: the two keys compare equal"
      refute int === float, "premise: the two keys are not identical"
    end

    test "contains a map beyond the small-map representation" do
      assert Enum.any?(E.maps(), &(map_size(&1) > 32)),
             "no map over 32 keys — iteration-order divergences stay invisible"
    end

    test "contains mixed key types and a nested value" do
      assert Enum.any?(E.maps(), fn m -> Enum.any?(Map.keys(m), &is_binary/1) end)
      assert Enum.any?(E.maps(), fn m -> Enum.any?(Map.values(m), &is_map/1) end)
    end
  end

  describe "keyword_lists" do
    test "contains duplicate keys, which Map.new collapses and Keyword.get does not" do
      dup =
        Enum.find(E.keyword_lists(), fn kw ->
          keys = Keyword.keys(kw)
          keys != Enum.uniq(keys)
        end)

      assert dup, "no keyword list with duplicate keys — the Map/Keyword divergence is invisible"

      # The divergence itself, on the actual battery input: this is the exact
      # trap a fix rewriting Keyword.get/2 as Map.get/2 falls into.
      [{key, _} | _] = dup

      assert Keyword.get(dup, key) != dup |> Map.new() |> Map.get(key),
             "the duplicate-key entry does not actually diverge between Keyword and Map"
    end

    test "contains two lists with the same pairs in different order" do
      sorted = Enum.map(E.keyword_lists(), &Enum.sort/1)

      assert length(sorted) != length(Enum.uniq(sorted)),
             "no order-only pair — order significance stays untested"
    end
  end

  describe "tuples" do
    test "spans arities including 0 and 1" do
      arities = E.tuples() |> Enum.map(&tuple_size/1) |> Enum.uniq()

      assert 0 in arities, "no empty tuple"
      assert 1 in arities, "no 1-tuple — easily confused with a bare value"
      assert Enum.count(arities) >= 4, "too few distinct arities to witness arity dependence"
    end

    test "contains the ok/error result idiom and a nested tuple" do
      assert Enum.any?(E.tuples(), &match?({:ok, _}, &1))
      assert Enum.any?(E.tuples(), &match?({:error, _}, &1))
      assert Enum.any?(E.tuples(), fn t -> tuple_size(t) == 2 and is_tuple(elem(t, 1)) end)
    end
  end

  describe "mixed_numeric" do
    test "contains a value pair that is `==` but not `===`" do
      vals = E.mixed_numeric()
      int = Enum.find(vals, &(is_integer(&1) and &1 == 1))
      float = Enum.find(vals, &(is_float(&1) and &1 == 1.0))

      assert int && float, "the battery needs both 1 and 1.0"
      assert int == float
      refute int === float
    end

    test "contains negative zero, which `==` cannot distinguish from zero" do
      assert Enum.any?(E.mixed_numeric(), &(&1 === -0.0)),
             "no -0.0 — a fix that normalises signs looks equivalent"

      [neg_zero, zero] = [
        Enum.find(E.mixed_numeric(), &(&1 === -0.0)),
        Enum.find(E.mixed_numeric(), &(&1 === 0.0))
      ]

      assert neg_zero == zero
      refute neg_zero === zero
    end

    test "contains a negative value witnessing rem/mod sign divergence" do
      neg = Enum.find(E.mixed_numeric(), &(is_integer(&1) and &1 < 0))

      assert neg, "no negative integer — the Python `%` transplant trap is invisible"

      assert rem(neg, 3) != Integer.mod(neg, 3),
             "the negative entry does not actually diverge between rem/2 and Integer.mod/2"
    end

    test "contains an integer too large to survive a float round trip" do
      big = Enum.find(E.mixed_numeric(), &(is_integer(&1) and &1 > 9_007_199_254_740_992))

      assert big, "no beyond-float-precision integer"

      assert trunc(big / 1) != big,
             "the large entry survives the round trip — it discriminates nothing"
    end
  end

  describe "the registry and the module agree" do
    # A dimension the mix task offers but the module does not export is a
    # crash at `--dim` time; one the module exports but the task does not know
    # is dead weight nobody can select.
    test "every dimension named by mix credence.equiv exists" do
      source = File.read!("lib/mix/tasks/credence.equiv.ex")

      names =
        ~r/@all_string_dims\s+\[(?<a>[^\]]*)\]|@collection_dims\s+\[(?<b>[^\]]*)\]|@struct_dims\s+\[(?<c>[^\]]*)\]|@all_dims\s+\[(?<d>[^\]]*)\]/
        |> Regex.scan(source)
        |> List.flatten()
        |> Enum.join(" ")
        |> then(&Regex.scan(~r/:([a-z_]+)/, &1))
        |> Enum.map(fn [_, n] -> String.to_atom(n) end)
        |> Enum.uniq()

      assert length(names) >= 10, "did not find the dimension registry — the regex needs updating"
      assert :structs in names, "did not read @struct_dims from the dimension registry"

      for dim <- names do
        assert function_exported?(E, dim, 0),
               "mix credence.equiv offers --dim #{dim} but Credence.EquivalenceInputs has no #{dim}/0"
      end
    end
  end

  defp key_identity_trap?(map) do
    map_size(map) == 2 and Map.has_key?(map, 1) and Map.has_key?(map, 1.0)
  end
end
