defmodule Credence.DispatchContentionTest do
  # `async: false`: this compiles ~2,000 candidate sources, and doing that
  # alongside the rest of the suite is the one thing worth not parallelising.
  use ExUnit.Case, async: false

  alias Credence.DispatchContention, as: Contention

  @moduledoc """
  T1.2 — the dispatch-simulation gate (docs/22), closing the Semantic half of
  docs/20's "No test pins ordering today".

  The property: when two live Semantic rules claim the same captured
  diagnostic, the winner must be decided by a **declared priority**, never by
  the alphabetical tiebreak in `Enum.sort_by(&{&1.priority(), &1})`. Ordering
  that falls out of a module name is ordering nobody chose, and in the Semantic
  round — `Enum.find`, first match wins — the loser does not run at all.
  """

  # Today's debt, frozen — the C13/C14 ratchet shape (docs/22 Part I §4.5:
  # "ratchets, not walls"). Each entry is a rule that wins a contended
  # diagnostic on a declared priority without naming the rule it beats. They
  # are ordered correctly; what is missing is the stated reason, so a later
  # reader cannot tell a deliberate ordering from an accident.
  #
  # The list may only shrink — the test below fails on a stale entry, so paying
  # one down forces its removal rather than letting it rot here.
  @ledger MapSet.new([
            {"FixApplyArityOne", "UndefinedFunction"},
            {"FixHallucinatedCalendarIsoAccessor", "UndefinedFunction"},
            {"FixHallucinatedNaiveDatetimeAccessor", "UndefinedFunction"},
            {"FixHallucinatedStreamDataFlatMap", "UndefinedFunction"},
            {"FixNimbleCsvDirectParse", "UndefinedFunction"},
            {"FixTruncatedSpecialForm", "FixCaseBranchAssignmentScope"},
            {"MissingUseExunitCase", "UndefinedFunction"},
            {"NoHallucinatedDefpstruct", "UndefinedFunction"},
            {"NoStreamDataIntegerTwoArgs", "UndefinedFunction"}
          ])

  setup_all do
    rules = Credence.Semantic.default_rules()
    diagnostics = Contention.captured_diagnostics(rules)

    {:ok,
     rules: rules,
     diagnostics: diagnostics,
     contentions: Contention.contentions(rules, diagnostics)}
  end

  describe "the live rule set" do
    test "every contended diagnostic is decided by priority, not by module name", ctx do
      offenders =
        for {diagnostic, [winner | losers]} <- ctx.contentions,
            loser <- losers,
            winner.priority() >= loser.priority() do
          "#{short(winner)} (#{winner.priority()}) beats #{short(loser)} " <>
            "(#{loser.priority()}) only alphabetically, on: #{excerpt(diagnostic)}"
        end

      assert offenders == [],
             """
             A diagnostic is claimed by more than one live Semantic rule, and the
             winner is decided by the alphabetical tiebreak rather than a declared
             priority (docs/20 §2). Renaming either rule would silently change
             which one runs — and in Semantic the loser does not run at all.

             Repair: give the rule that should own the diagnostic an explicit
             priority in the 100–499 band and state the reason in its moduledoc,
             naming the rule it must precede (docs/20 §1). Or narrow one
             `match?/1` so the two sets are disjoint (docs/20 §3).

             #{Enum.join(offenders, "\n")}
             """
    end

    test "each contention winner names the rule it must precede (docs/20 §1)", ctx do
      undocumented = undocumented_pairs(ctx.contentions)

      assert MapSet.difference(undocumented, @ledger) |> Enum.sort() == [],
             """
             A rule wins a contended diagnostic but does not say why. docs/20 §1:
             a priority is an assertion, and the reason belongs in the moduledoc
             in one sentence naming the other rule — "a priority with no stated
             reason is indistinguishable from a typo".

             #{undocumented |> MapSet.difference(@ledger) |> Enum.sort() |> Enum.map(fn {w, l} -> "  #{w} does not mention #{l}" end) |> Enum.join("\n")}
             """
    end

    test "the ledger only shrinks — no entry that is already paid down", ctx do
      stale = MapSet.difference(@ledger, undocumented_pairs(ctx.contentions))

      assert Enum.sort(stale) == [],
             """
             These pairs are documented (or no longer contended), so they are no
             longer debt — delete them from @ledger. A ratchet that keeps paid
             entries stops being a ratchet: it would let a regression slide back
             in under an entry that is no longer earning its place.

             #{stale |> Enum.sort() |> Enum.map(fn {w, l} -> "  #{w} -> #{l}" end) |> Enum.join("\n")}
             """
    end
  end

  # The gate above is only as good as the set it ran over. If `candidates/1`
  # or `compile_and_capture/1` quietly stopped producing diagnostics, both
  # assertions would pass over an empty list and say nothing — which is exactly
  # how the self-corruption gate went vacuous the moment its ledger emptied
  # (docs/21, T3.10a). These pin the machinery rather than the result, so they
  # hold whether or not any real contention exists.
  describe "the gate cannot pass vacuously" do
    test "the captured diagnostic set is populated", ctx do
      assert length(ctx.diagnostics) > 300,
             "only #{length(ctx.diagnostics)} diagnostics captured — the witness " <>
               "candidates or the compiler capture stopped working, and the gate " <>
               "above is now asserting nothing"
    end

    test "the live rule set is populated", ctx do
      assert length(ctx.rules) > 80
    end

    test "CONTROL: two rules claiming one diagnostic are detected", ctx do
      diagnostic = %{
        severity: :error,
        message: "undefined function ghost/0",
        position: 1,
        file: "x.ex"
      }

      rules = Contention.dispatch_order([ContentionProbe.Greedy, ContentionProbe.AlsoGreedy])

      assert [{^diagnostic, claimers}] = Contention.contentions(rules, [diagnostic])
      assert claimers == [ContentionProbe.AlsoGreedy, ContentionProbe.Greedy]

      # ...and the tie is what the gate calls an offence: equal priorities, so
      # the winner is whichever module name sorts first.
      [winner | [loser]] = claimers
      assert winner.priority() == loser.priority()

      # Sanity: the real set does not accidentally contain these.
      refute ContentionProbe.Greedy in ctx.rules
    end

    test "CONTROL: a diagnostic with one claimer is not reported as contended" do
      diagnostic = %{
        severity: :error,
        message: "undefined function ghost/0",
        position: 1,
        file: "x.ex"
      }

      assert Contention.contentions([ContentionProbe.Greedy, ContentionProbe.Fussy], [diagnostic]) ==
               []
    end

    test "CONTROL: a raising match?/1 counts as a decline, not a claim" do
      diagnostic = %{
        severity: :error,
        message: "undefined function ghost/0",
        position: 1,
        file: "x.ex"
      }

      assert Contention.claimers([ContentionProbe.Exploding, ContentionProbe.Greedy], diagnostic) ==
               [ContentionProbe.Greedy]
    end
  end

  defp undocumented_pairs(contentions) do
    for {_diagnostic, [winner | losers]} <- contentions,
        loser <- losers,
        not names?(winner, loser),
        into: MapSet.new() do
      {short(winner), short(loser)}
    end
  end

  defp short(rule), do: rule |> Module.split() |> List.last()

  defp excerpt(diagnostic), do: String.slice(diagnostic.message, 0, 90)

  defp names?(winner, loser) do
    case Code.fetch_docs(winner) do
      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} -> String.contains?(moduledoc, short(loser))
      _ -> false
    end
  end
end

# Fabricated claimants for the controls. Deliberately not `use
# Credence.Semantic.Rule` — they are not rules and must never be discovered by
# `discover_rules/1`; the machinery only ever asks for `match?/1` and
# `priority/0`, which is what makes it testable at all.
defmodule ContentionProbe.Greedy do
  def match?(%{message: message}), do: String.contains?(message, "ghost")
  def priority, do: 500
end

defmodule ContentionProbe.AlsoGreedy do
  def match?(%{message: message}), do: String.contains?(message, "ghost")
  def priority, do: 500
end

defmodule ContentionProbe.Fussy do
  def match?(%{message: message}), do: String.contains?(message, "nothing matches this")
  def priority, do: 500
end

defmodule ContentionProbe.Exploding do
  def match?(_diagnostic), do: raise("match?/1 blew up")
  def priority, do: 499
end
