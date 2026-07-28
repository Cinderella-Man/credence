defmodule Credence.Corpus.BudgetTest do
  @moduledoc """
  Unit tests for `Credence.Corpus.Budget` — the arithmetic and the four
  violation classes behind the corpus-findings budget gate (docs/12 C13).

  `test/corpus/findings_budget_test.exs` is the gate; it asserts
  `Budget.violations/3` returns `[]` for the committed files and the frozen
  policy. That test can only ever be seen GREEN, so **every violation class it
  relies on is driven RED here**, through the same function, on inputs that are
  the committed data with one number moved. A gate whose failure path has never
  executed is not a gate — this file is where its failure path executes.
  """
  use ExUnit.Case, async: true

  alias Credence.Corpus.Budget

  @ledger %{"big" => 500, "medium" => 150}
  @policy [cap: 100, grandfathered: @ledger]

  # A clean world: `big` and `medium` are on the ledger and under their
  # ceilings; `small` is off it and under the cap; the published file agrees.
  @counts %{"big" => 400, "medium" => 120, "small" => 40}

  describe "counts/1" do
    test "counts one finding per identity line" do
      assert Budget.counts(["a.ex:1  r", "a.ex:2  r"]) == %{"r" => 2}
    end

    test "counts an (xN) line as N — the multiplicity IS the debt" do
      assert Budget.counts(["a.ex:1  r  (x3)"]) == %{"r" => 3}
    end

    test "mixes plain and (xN) lines" do
      assert Budget.counts(["a.ex:1  r", "a.ex:2  r  (x3)", "a.ex:3  s"]) ==
               %{"r" => 4, "s" => 1}
    end

    test "ignores comments and blanks, exactly as the snapshot reader does" do
      assert Budget.counts(["# header", "", "a.ex:1  r"]) == %{"r" => 1}
    end

    test "is empty for no input — the vacuity the gate has its own test for" do
      assert Budget.counts([]) == %{}
    end

    test "does not attribute a finding to a rule named in the PATH" do
      # The trap Findings.only_rule/2 documents: the corpus ships credo, styler
      # and recode, whose files are named after checks.
      assert Budget.counts(["credo/lib/credo/check/no_uniq_then_count.ex:7  prefer_erlang_float"]) ==
               %{"prefer_erlang_float" => 1}
    end
  end

  describe "total/1 and rank/1" do
    test "total sums every rule" do
      assert Budget.total(@counts) == 560
    end

    test "rank orders by count descending, then by name" do
      assert Budget.rank(%{"b" => 5, "a" => 5, "c" => 9}) == [{"c", 9}, {"a", 5}, {"b", 5}]
    end
  end

  describe "render/2 and parse/1" do
    test "round-trip: parse(render(counts)) == counts" do
      assert Budget.parse(Budget.render(@counts)) == @counts
    end

    test "round-trips the real committed budget, not just a toy" do
      published = Budget.published()
      assert published != %{}
      assert Budget.parse(Budget.render(published)) == published
    end

    test "the rendered body ranks rules, so the file's own order is the paydown order" do
      rows =
        @counts
        |> Budget.render()
        |> String.split("\n")
        |> Enum.reject(&(String.trim(&1) == "" or String.starts_with?(&1, "#")))

      assert rows == ["  400  big", "  120  medium", "   40  small"]
    end

    test "the header publishes the total, the rule count and the over-cap share" do
      body = Budget.render(@counts)
      assert body =~ "# TOTAL 560 accepted findings across 3 rules."
      assert body =~ "2 over the cap of 100"
      assert body =~ "1 at or under the cap"
    end

    test "renders an empty budget without dividing by zero" do
      assert Budget.render(%{}) =~ "EMPTY"
      assert Budget.parse(Budget.render(%{})) == %{}
    end

    test "parse raises on a row it cannot read rather than dropping it" do
      # Silently dropping would shrink the published total — the one direction
      # that must never be quiet.
      assert_raise ArgumentError, ~r/cannot parse row/, fn ->
        Budget.parse("# ok\n400  big\nnot a budget row\n")
      end
    end

    test "parse raises on a duplicated rule rather than letting the last win" do
      assert_raise ArgumentError, ~r/appears twice/, fn ->
        Budget.parse("400  big\n120  big\n")
      end
    end
  end

  describe "violations/3 — the clean baseline" do
    test "a budget that agrees with the snapshot and respects the policy is []" do
      assert Budget.violations(@counts, @counts, @policy) == []
    end

    test "the committed files and the shipped policy are clean" do
      # The same assertion the gate makes, restated here so this file fails too
      # if the committed state drifts — and so the RED cases below are known to
      # be red *because of the perturbation*, not because the baseline was
      # already broken.
      counts = Budget.counts(Credence.Corpus.Findings.snapshot_lines())
      assert Budget.violations(counts, Budget.published(), grandfathered: ledger_of(counts)) == []
    end
  end

  describe "violations/3 — :out_of_sync (the published view drifted from the snapshot)" do
    test "fires when the snapshot grew and nobody regenerated the budget" do
      counts = %{@counts | "small" => 41}

      assert Budget.violations(counts, @counts, @policy) == [
               {:out_of_sync, "small", 40, 41}
             ]
    end

    test "fires when the snapshot SHRANK — a paydown must be published too" do
      counts = %{@counts | "small" => 10}

      assert Budget.violations(counts, @counts, @policy) == [
               {:out_of_sync, "small", 40, 10}
             ]
    end

    test "fires for a rule present in only one of the two files" do
      assert Budget.violations(Map.put(@counts, "fresh", 3), @counts, @policy) ==
               [{:out_of_sync, "fresh", 0, 3}]

      assert Budget.violations(@counts, Map.put(@counts, "gone", 3), @policy) ==
               [{:out_of_sync, "gone", 3, 0}]
    end

    test "a missing budget file reports every rule, rather than passing vacuously" do
      violations = Budget.violations(@counts, %{}, @policy)
      assert length(violations) == 3
      assert Enum.all?(violations, &(elem(&1, 0) == :out_of_sync))
    end
  end

  describe "violations/3 — :over_cap (a rule off the ledger blowing the budget)" do
    test "fires for a NEW rule that lands style-heavy" do
      counts = Map.put(@counts, "fresh", 429)

      assert {:over_cap, "fresh", 429, 100} in Budget.violations(counts, counts, @policy)
    end

    test "does not fire at exactly the cap, and does fire one over it" do
      at_cap = Map.put(@counts, "fresh", 100)
      assert Budget.violations(at_cap, at_cap, @policy) == []

      over = Map.put(@counts, "fresh", 101)
      assert {:over_cap, "fresh", 101, 100} in Budget.violations(over, over, @policy)
    end

    test "does not fire for a grandfathered rule — that is what the ledger is for" do
      counts = %{@counts | "big" => 450}
      refute Enum.any?(Budget.violations(counts, counts, @policy), &(elem(&1, 0) == :over_cap))
    end

    test "reports the worst offender first" do
      counts = Map.merge(@counts, %{"a_lot" => 300, "a_bit" => 110})

      over =
        counts
        |> Budget.violations(counts, @policy)
        |> Enum.filter(&(elem(&1, 0) == :over_cap))

      assert over == [{:over_cap, "a_lot", 300, 100}, {:over_cap, "a_bit", 110, 100}]
    end
  end

  describe "violations/3 — :over_grandfather (a ceiling is a high-water mark)" do
    test "fires when a grandfathered rule grows past its adoption-day number" do
      counts = %{@counts | "big" => 501}

      assert {:over_grandfather, "big", 501, 500} in Budget.violations(counts, counts, @policy)
    end

    test "does not fire at exactly the ceiling" do
      counts = %{@counts | "big" => 500}
      assert Budget.violations(counts, counts, @policy) == []
    end

    test "a grandfathered rule may fall freely — the ratchet is one-way" do
      counts = %{@counts | "big" => 101}
      assert Budget.violations(counts, counts, @policy) == []
    end
  end

  describe "violations/3 — :graduated (the ledger has to shrink)" do
    test "fires when a grandfathered rule is paid down to the cap" do
      counts = %{@counts | "medium" => 100}

      assert {:graduated, "medium", 100, 100} in Budget.violations(counts, counts, @policy)
    end

    test "fires when a grandfathered rule is paid down to zero and vanishes" do
      counts = Map.delete(@counts, "medium")

      assert {:graduated, "medium", 0, 100} in Budget.violations(counts, counts, @policy)
    end

    test "is what makes a paydown permanent" do
      # Paid down past the cap, the rule must leave the ledger; once off it, the
      # SAME count that was legal at 120 under the ledger is an :over_cap
      # violation if it ever comes back.
      paid_down = %{@counts | "medium" => 90}
      assert {:graduated, "medium", 90, 100} in Budget.violations(paid_down, paid_down, @policy)

      graduated_policy = [cap: 100, grandfathered: Map.delete(@ledger, "medium")]
      refile = %{@counts | "medium" => 120}

      assert {:over_cap, "medium", 120, 100} in Budget.violations(
               refile,
               refile,
               graduated_policy
             )
    end
  end

  describe "explain/1" do
    test "an empty violation list explains itself as holding" do
      assert Budget.explain([]) == "the accepted-findings budget holds"
    end

    test "every violation class renders a remedy, not just a number" do
      counts = %{"fresh" => 429}
      message = Budget.explain(Budget.violations(counts, %{}, @policy))

      assert message =~ "fresh"
      assert message =~ "429"
      assert message =~ "mix credence.corpus --update-budget"
      assert message =~ "@grandfathered"
    end

    test "names the file to edit for a ledger violation" do
      counts = %{@counts | "big" => 501}

      assert Budget.explain(Budget.violations(counts, counts, @policy)) =~
               "test/corpus/findings_budget_test.exs"
    end
  end

  describe "deltas/2 — what an accept costs, at the moment it is made" do
    test "is empty when nothing moved" do
      assert Budget.deltas(@counts, @counts) == []
    end

    test "reports from → to for every rule that moved, biggest change first" do
      to = Map.merge(@counts, %{"small" => 45, "big" => 300, "fresh" => 7})

      assert Budget.deltas(@counts, to) == [
               {"big", 400, 300},
               {"fresh", 0, 7},
               {"small", 40, 45}
             ]
    end

    test "reports a rule that stopped firing entirely" do
      assert Budget.deltas(@counts, Map.delete(@counts, "small")) == [{"small", 40, 0}]
    end
  end

  # The gate's own ledger is frozen in findings_budget_test.exs; rebuilding it
  # here from the committed counts would just restate that file. Instead derive
  # the *shape* the ledger must have — exactly the rules over the cap — which is
  # the invariant that file asserts, so the baseline check above is meaningful
  # without duplicating fifteen numbers that must not drift between two files.
  defp ledger_of(counts) do
    for {rule, count} <- counts, count > Budget.default_cap(), into: %{}, do: {rule, count}
  end
end
