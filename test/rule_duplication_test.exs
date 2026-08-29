defmodule Credence.RuleDuplicationTest do
  @moduledoc """
  Gate: no two Pattern rules are duplicates of one another.

  The signal is `Credence.RuleDuplication` — see its moduledoc for why it is two
  signals intersected rather than one, and why the threshold is 0.6. This file
  holds the ledger of pairs the signal reports today, each with the triage that
  cleared it, and the controls proving the gate can go red.

  ## Why this gate exists

  docs/12 C11 named three "duplicate clusters" by reading. Running them refuted
  two and confirmed one — and the one it confirmed
  (`no_list_delete_at_length` ~ `no_list_delete_at_with_length`: same target,
  same repair, identical behaviour on every shape probed, and only the first
  ever fired) was not one of the three. Reading finds rules that *sound* alike;
  only running them finds rules that *are* alike.
  """
  use ExUnit.Case, async: true

  alias Credence.RuleDuplication

  @threshold 0.6

  # ── The ledger ──────────────────────────────────────────────────────────
  #
  # Every pair the intersection reports today, with why it is not a duplicate.
  # Each was triaged by EXECUTION — probing inputs on either side of the two
  # rules' boundary — not by reading their moduledocs.
  #
  # This is a ratchet in the C13/C14 idiom: the list may shrink, never grow. A
  # new pair crossing both signals is a new rule that keys on the same thing as
  # an existing one and never catches anything it misses, which is the moment to
  # look, before it ships.
  #
  # It has already shrunk once, by itself. `NoSortThenAt ⊇ NoSortThenReverse`
  # was here until the D5 backfill added 35 `## Bad` examples to the shared
  # corpus, at which point the two stopped containing each other — the entry's
  # own note had said the containment looked like an artefact of each rule
  # firing on exactly one snippet, and growing the corpus proved it. Worth
  # knowing about this signal: containment gets STRICTER as the corpus grows, so
  # a pair surviving a larger corpus means more than one surviving a small one.
  @ledger [
    # RETIRED 2026-08-17 — the pair stopped scoring because the overlap was
    # removed, which is what this ratchet is for. It used to read: "both;
    # IntegerKey no_ops and AtomFirstArg completes the repair. The `:no_op` is the
    # cascade working, not a rule failing."
    #
    # That defence held for the FIX and not for the REPORT. On
    # `Keyword.get(:timeout, 5000)` IntegerKey told the user "integer keys always
    # crash" and suggested `List.last/1`, which is the wrong advice — the defect is
    # swapped arguments, and AtomFirstArg says so. Two findings where one misleads
    # is worse than one, whichever rule ends up doing the repair.
    #
    # IntegerKey now declines an atom-literal first argument in both callbacks, so
    # the shape has exactly one owner. `no_keyword_get_integer_key_check_test.exs`
    # pins the boundary from both sides, including that the sibling still claims it.

    # A general rule deferring to a specific one, which is the cascade the
    # Pattern round is built on. Probed:
    #   Enum.take(nums, -3)              -> NoEnumTakeNegative alone -> Enum.slice/2
    #   sort() |> take(-3)               -> NoEnumTakeNegative no_ops, the specific
    #                                       rule rewrites to sort(:desc) |> take |> reverse
    #   sort_by(& &1.a) |> take(-3)      -> NoEnumTakeNegative alone (the specific
    #                                       rule requires `Enum.sort/1`)
    {Credence.Pattern.NoEnumTakeNegative, Credence.Pattern.PreferDescSortOverNegativeTake}
  ]

  describe "the ledger is a ratchet" do
    test "no Pattern rule pair is a duplicate that is not already ledgered" do
      rules = Credence.MetaTestSupport.rules()
      corpus = RuleDuplication.corpus(rules)

      # A vacuity floor on the machinery itself, not on the result. T3.10a's
      # lesson: a check whose only evidence is "it found nothing" cannot tell
      # "clean" from "broken". If the corpus collapses — a moduledoc format
      # change, a parse regression — this gate would pass by having nothing to
      # compare, and would say so nowhere.
      assert length(corpus) >= 150,
             "shared corpus collapsed to #{length(corpus)} snippets; the gate " <>
               "cannot distinguish clean from broken below ~150"

      signatures = Map.new(rules, &{&1, RuleDuplication.signature(&1)})
      firing = RuleDuplication.firing_sets(rules, corpus)

      assert Enum.count(firing, fn {_rule, set} -> MapSet.size(set) > 0 end) >= 100,
             "fewer than 100 rules fire on the shared corpus; the containment " <>
               "signal has gone silent"

      pairs = RuleDuplication.duplicate_pairs(signatures, firing, @threshold)
      new = gate_offenders(pairs, firing, @ledger)

      assert new == [],
             """
             New rule pair(s) score >= #{@threshold} on signature overlap AND one
             never fires on anything the other misses:

             #{Enum.map_join(new, "\n", fn {a, b, s} -> "  #{s}  #{inspect(a)} contains #{inspect(b)}" end)}

             That is the shape of a duplicate. Probe both rules on inputs either
             side of their boundary before adding them to @ledger — the pair
             already there is overlapping, not redundant, and its note says why.
             """
    end

    test "every ledgered pair still exists and still scores; retire it otherwise" do
      rules = Credence.MetaTestSupport.rules()
      corpus = RuleDuplication.corpus(rules)
      signatures = Map.new(rules, &{&1, RuleDuplication.signature(&1)})
      firing = RuleDuplication.firing_sets(rules, corpus)

      reported =
        MapSet.new(RuleDuplication.duplicate_pairs(signatures, firing, @threshold), fn {a, b, _} ->
          {a, b}
        end)

      stale = Enum.reject(@ledger, &(&1 in reported))

      assert stale == [],
             "ledgered pair(s) no longer score — delete them so the ledger only shrinks: #{inspect(stale)}"
    end
  end

  # ── Controls: a gate nobody has seen red is unverified ──────────────────

  describe "positive control" do
    # Two fabricated rules, one a strict weakening of the other: SUPERSET fires
    # on `Enum.map/2` under any name, SUBSET only when the function is `map`
    # AND the module is `Enum` — so it can never catch anything SUPERSET misses.
    # This is the shape of the pair this project actually retired.
    defmodule SupersetRule do
      def check(ast, _opts) do
        {_ast, hits} =
          Macro.prewalk(ast, [], fn
            {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, _} = n, acc -> {n, [:hit | acc]}
            n, acc -> {n, acc}
          end)

        hits
      end
    end

    defmodule SubsetRule do
      def check(ast, _opts) do
        {_ast, hits} =
          Macro.prewalk(ast, [], fn
            {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [_, _]} = n, acc -> {n, [:hit | acc]}
            n, acc -> {n, acc}
          end)

        hits
      end
    end

    @superset_source """
    defmodule SupersetRule do
      def check(ast, _opts) do
        {_ast, hits} = Macro.prewalk(ast, [], fn
          {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, _} = n, acc -> {n, [:hit | acc]}
          n, acc -> {n, acc}
        end)
      end
    end
    """

    @subset_source """
    defmodule SubsetRule do
      def check(ast, _opts) do
        {_ast, hits} = Macro.prewalk(ast, [], fn
          {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [_, _]} = n, acc -> {n, [:hit | acc]}
          n, acc -> {n, acc}
        end)
      end
    end
    """

    test "the gate reports a fabricated rule that subsumes another" do
      corpus = RuleDuplication.corpus(Credence.MetaTestSupport.rules())

      signatures = %{
        SupersetRule => RuleDuplication.signature_from_source(@superset_source, :superset_rule),
        SubsetRule => RuleDuplication.signature_from_source(@subset_source, :subset_rule)
      }

      firing = RuleDuplication.firing_sets([SupersetRule, SubsetRule], corpus)

      # The control is only meaningful if the fabricated rules actually fire.
      assert MapSet.size(firing[SubsetRule]) > 0
      assert MapSet.subset?(firing[SubsetRule], firing[SupersetRule])

      pairs = RuleDuplication.duplicate_pairs(signatures, firing, @threshold)

      assert gate_offenders(pairs, firing, []) == [
               {SupersetRule, SubsetRule, 1.0}
             ]
    end

    test "the ledger cannot hide a pair whose firing sets become identical" do
      pair = {SupersetRule, SubsetRule, 1.0}
      identical = MapSet.new([0, 2])
      firing = %{SupersetRule => identical, SubsetRule => identical}

      assert gate_offenders([pair], firing, [{SupersetRule, SubsetRule}]) == [pair]
    end
  end

  describe "negative controls — each signal alone must not be enough" do
    defmodule SameWordsDifferentTargetRule do
      def check(ast, _opts) do
        {_ast, hits} =
          Macro.prewalk(ast, [], fn
            {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, _} = n, acc -> {n, [:hit | acc]}
            n, acc -> {n, acc}
          end)

        hits
      end
    end

    @same_words_source """
    defmodule SameWordsDifferentTargetRule do
      def check(ast, _opts) do
        {_ast, hits} = Macro.prewalk(ast, [], fn
          {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, _} = n, acc -> {n, [:hit | acc]}
          n, acc -> {n, acc}
        end)
      end
    end
    """

    test "signature overlap alone does not report a pair with disjoint firing" do
      corpus = RuleDuplication.corpus(Credence.MetaTestSupport.rules())

      map_sig =
        RuleDuplication.signature_from_source(
          """
          defmodule OnlyMapRule do
            def check(ast, _opts) do
              {_ast, hits} = Macro.prewalk(ast, [], fn
                {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, _} = n, acc -> {n, [:hit | acc]}
                n, acc -> {n, acc}
              end)
            end
          end
          """,
          :only_map_rule
        )

      reduce_sig =
        RuleDuplication.signature_from_source(
          @same_words_source,
          :same_words_different_target_rule
        )

      # They score high — nearly the same vocabulary, one atom apart...
      assert RuleDuplication.jaccard(map_sig, reduce_sig) >= @threshold

      # ...but `Enum.reduce` is not `Enum.map`, so containment fails and the
      # gate stays quiet. Without this half, the gate would report 19 pairs.
      firing =
        RuleDuplication.firing_sets(
          [SupersetRule, SameWordsDifferentTargetRule],
          corpus
        )

      signatures = %{
        SupersetRule => map_sig,
        SameWordsDifferentTargetRule => reduce_sig
      }

      assert RuleDuplication.duplicate_pairs(signatures, firing, @threshold) == []
    end

    test "containment alone does not report a pair with unrelated signatures" do
      corpus = RuleDuplication.corpus(Credence.MetaTestSupport.rules())
      rules = Credence.MetaTestSupport.rules()
      firing = RuleDuplication.firing_sets(rules, corpus)
      signatures = Map.new(rules, &{&1, RuleDuplication.signature(&1)})

      # At threshold 0.0 the signature half is disabled and only containment
      # remains. It reports pairs that share nothing — measured:
      # RemoveUnreachableClausesAfterCatchall contains NoDocFalseOnPrivate, two
      # rules with no relationship, at a signature score of 0.08.
      containment_only = RuleDuplication.duplicate_pairs(signatures, firing, 0.0)
      both = RuleDuplication.duplicate_pairs(signatures, firing, @threshold)

      assert length(containment_only) > length(both),
             "containment alone should be noisier than the intersection; if it is " <>
               "not, the signature half is doing nothing"
    end
  end

  defp gate_offenders(pairs, firing, ledger) do
    Enum.reject(pairs, fn {a, b, _score} ->
      {a, b} in ledger and not MapSet.equal?(firing[a], firing[b])
    end)
  end
end
