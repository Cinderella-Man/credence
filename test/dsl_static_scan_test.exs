defmodule Credence.DslStaticScanTest do
  @moduledoc """
  C14 — the **source-side** DSL-safety gate, and the frozen ledger of the rules
  that were already unclassified when it was adopted (docs/12 C14, docs/19 §2
  row B, Rule Standard item 5).

  ## Why a second DSL gate exists

  `Credence.Pattern.DslSafetyClassificationTest` asks the empirical question: it
  runs each rule's real fix over that rule's own `*_fix_test.exs` fixtures and
  diffs the reinterpreted-construct multiset. That oracle is exact for the inputs
  it sees and **blind to everything else** — a rule whose fixtures never happen
  to exhibit the reinterpreted construct produces an empty delta and passes
  silently. docs/12 C14 is precisely that gap, and the `unsafe_in_dsl` retrofit
  (PR #20) is how it was discovered: 14 rules were classified *after* the whole
  class had shipped and been firing inside Ash/Ecto/Nx blocks for ~2 months.

  This gate reads the rule's **source** instead of its fixtures. It never runs a
  fix, so it cannot say a rewrite is wrong; it says only whether the fix code
  builds or destructures a construct one of the three known DSL families
  reinterprets, and whether the rule's matchers are anchored on shapes that
  cannot occur inside a DSL expression. Fixtures catch what the code *does*;
  source catches what the code *could* do on an input no fixture supplied.

  ## What this gate actually requires

  Not a safety proof — a **deliberate classification**. Rule Standard item 5 is
  "`unsafe_in_dsl/0` declared deliberately, even if the answer is `[]`", and the
  reason the answer may be `[]` is that at runtime a considered `[]` and the
  inherited default `[]` are the same value. Only the source distinguishes them.
  So a rule passes by being in any of four buckets:

    * `:declared`      — its source contains an explicit `def unsafe_in_dsl`;
    * `:verified_safe` — it is on `@verified_dsl_safe` with a written reason;
    * `:anchored`      — every matcher clause is keyed on a `def`/`defp` head or
                         another form no DSL expression grammar admits;
    * `:no_construct`  — its fix code touches no reinterpreted construct at all.

  `:possibly_unsafe` is the fifth bucket and the only failing one. It is a
  **static** verdict: "this fix builds or consumes a reinterpreted construct and
  nothing in its matchers rules out a DSL expression". The correct response is a
  human reading the rule, never an automatic `unsafe_in_dsl/0` edit — which is
  why nothing here writes that callback.

  ## The ledger, and why it is not a wall

  40 of 155 Pattern rules were in `:possibly_unsafe` when this gate was adopted.
  Failing all 40 on day one would be the mistake docs/19 §2 row A already made
  once — a gate nobody can get green teaches people to disable it. So the 40 are
  frozen in `@unclassified` as debt, and the gate asserts the flagged set equals
  that ledger **exactly**, in both directions:

    * a rule that becomes flagged and is not on the ledger fails — a new rule
      cannot land unclassified, which is the whole point;
    * a rule that leaves the flagged set must leave the ledger — so the ledger
      ratchets down and a paydown is permanent, exactly as C13's grandfather
      ledger works for corpus findings.

  ## Reading the ledger

  It is split by evidence strength, because the two halves are not equally
  suspicious:

    * **17 rules name a real family** — the construct they touch is one
      `Credence.DslGuard`'s moduledoc attributes to Ash.Expr, Ecto.Query or
      Nx.Defn. These are the paydown order.
    * **23 are `:unattributed` only** — the construct is in the union oracle
      (`@ops ++ @ctrl` in the classification meta-test) but no family in
      `DslGuard` reinterprets it. Weaker evidence by construction, and worth
      saying out loud rather than letting the count imply 40 equal risks.

  Within each half, the scan's own rank is the order: 3 = the fix **builds** a
  reinterpreted node, 2 = builds via an assembled source string, 1 = only
  **destructures** one, 0 = a bare construct atom used as a value.
  """
  use ExUnit.Case, async: true

  alias Credence.DslStaticScan

  # Rules already in `:possibly_unsafe` when this gate was adopted (2026-07-28).
  # Frozen debt, not approval: each still needs a human to read it and either
  # declare `unsafe_in_dsl/0` or earn a `@verified_dsl_safe` entry. This list may
  # only shrink — see "The ledger, and why it is not a wall" above.
  #
  # ── EMPTY. The 40 rules frozen here on 2026-07-28 were all classified in the
  # C14 sweep of 2026-08-16: 10 declare a family they diverge in, 9 declare a
  # deliberate `[]`, and 21 earned a `@verified_dsl_safe` reason. Requirement 5
  # of the Rule Standard is now satisfied by every Pattern rule, not merely
  # gated against getting worse.
  #
  # The gate does NOT become vacuous at zero: its controls (below) drive the
  # scanner over fabricated rules and assert population floors, so "nobody is
  # unclassified" and "the scanner stopped working" stay distinguishable — the
  # T3.10a lesson, which this ledger reaching empty is exactly the moment for.
  @unclassified_attributed ~w()

  @unclassified_unattributed ~w()

  @unclassified @unclassified_attributed ++ @unclassified_unattributed

  setup_all do
    entries = DslStaticScan.scan("lib/pattern", DslStaticScan.verified_dsl_safe_names())
    {:ok, entries: entries, flagged: for(e <- entries, e.bucket == :possibly_unsafe, do: e.name)}
  end

  describe "the gate cannot pass vacuously" do
    @tag :tmp_dir
    test "fabricated rules exercise every decision that can empty the ledger", %{tmp_dir: tmp_dir} do
      sources = [
        {"construct",
         "defmodule FabricatedConstruct do\n  def fix_patches(_, _), do: {:if, [], []}\nend"},
        {"reachable",
         "defmodule FabricatedReachable do\n  def fix_patches(_, _), do: helper()\n  defp helper, do: {:if, [], []}\nend"},
        {"anchored",
         "defmodule FabricatedAnchored do\n  def fix_patches({:def, _, _}, _), do: {:if, [], []}\nend"},
        {"declared",
         "defmodule FabricatedDeclared do\n  def unsafe_in_dsl, do: []\n  def fix_patches(_, _), do: {:if, [], []}\nend"}
      ]

      Enum.each(sources, fn {name, source} ->
        File.write!(Path.join(tmp_dir, name <> ".ex"), source)
      end)

      buckets = tmp_dir |> DslStaticScan.scan([]) |> Map.new(&{&1.name, &1.bucket})

      assert buckets == %{
               "anchored" => :anchored,
               "construct" => :possibly_unsafe,
               "declared" => :declared,
               "reachable" => :possibly_unsafe
             }
    end

    test "the scan sees every Pattern rule", %{entries: entries} do
      live = length(Credence.Pattern.default_rules())

      assert length(entries) == live,
             "the scan read #{length(entries)} rule files but Credence.Pattern.default_rules/0 " <>
               "has #{live}. Every check below is over the scanned set, so a scan that silently " <>
               "reads fewer files than exist passes while saying nothing."
    end

    test "the construct universe covers every construct DslGuard attributes to a family" do
      # Union of `Credence.DslGuard`'s per-family lists: Ash.Expr rereads `!`/`not`,
      # Ecto.Query rejects `!`/`&&`/`||`/`==`/`!=` and requires `is_nil`, Nx.Defn
      # rereads `==`/`and`/`if`. A universe missing one of these would quietly stop
      # flagging the rules that touch it — green, and blind.
      required = ~w(! not && || == != is_nil and if)a
      missing = required -- DslStaticScan.constructs()

      assert missing == [],
             "the scan's construct universe is missing #{inspect(missing)}, which DslGuard names " <>
               "as reinterpreted. Rules touching those would land in :no_construct and pass."
    end

    test "the allowlist is read from the classification meta-test, not duplicated" do
      names = DslStaticScan.verified_dsl_safe_names()

      refute names == [],
             "@verified_dsl_safe parsed to zero entries. Either the attribute moved or its shape " <>
               "changed — and either way every rule on it would silently become unclassified."

      assert "avoid_length_guard_less_than2" in names,
             "the allowlist parsed, but without its known first entry — the shape changed."
    end

    test "every rule lands in exactly one known bucket", %{entries: entries} do
      known = [:declared, :verified_safe, :anchored, :possibly_unsafe, :no_construct]
      unknown = entries |> Enum.map(& &1.bucket) |> Enum.uniq() |> Enum.reject(&(&1 in known))

      assert unknown == [], "unknown bucket(s): #{inspect(unknown)}"
    end

    test "the live scan retains classified and construct-bearing populations", %{entries: entries} do
      tally = DslStaticScan.tally(entries)
      classified = Map.get(tally, :declared, 0) + Map.get(tally, :verified_safe, 0)
      construct_bearing = length(entries) - Map.get(tally, :no_construct, 0)

      assert classified >= 90,
             "only #{classified} rules remain explicitly classified; the live floor is 90"

      assert construct_bearing >= 50,
             "only #{construct_bearing} rules remain construct-bearing; the live floor is 50"
    end
  end

  describe "the ledger" do
    test "names only live Pattern rules" do
      live =
        Credence.Pattern.default_rules()
        |> Enum.map(&Credence.RuleName.from_module(&1).snake)
        |> MapSet.new()

      stale = Enum.reject(@unclassified, &MapSet.member?(live, &1))

      assert stale == [],
             "@unclassified names rules that no longer exist: #{inspect(stale)}. Delete them."
    end

    test "has no duplicates, within or across its two halves" do
      dupes = @unclassified -- Enum.uniq(@unclassified)
      assert dupes == [], "@unclassified lists #{inspect(dupes)} more than once."
    end
  end

  describe "the gate" do
    test "no rule is unclassified except the frozen ledger", %{flagged: flagged} do
      new = Enum.sort(flagged -- @unclassified)

      assert new == [],
             """

             #{length(new)} Pattern rule(s) touch a construct a DSL family reinterprets, and are
             neither declared nor allowlisted:

             #{Enum.map_join(new, "\n", &"    #{&1}")}

             This is not a claim that the rule is wrong. It is a claim that nobody has said either
             way, and at runtime a considered `unsafe_in_dsl: []` and the inherited default are the
             same value — so only the source can carry the decision. Do one of:

               * declare `def unsafe_in_dsl, do: [...]` in the rule (`[]` is a fine answer, and
                 the deliberate one is what item 5 of the Rule Standard asks for);
               * add it to `@verified_dsl_safe` in test/dsl_safety_classification_test.exs with
                 the reason — almost always that it matches only a def/defp head or an existing
                 `case`, neither of which can sit inside a DSL expression;
               * narrow the matcher so it cannot fire inside a DSL expression at all.

             Adding it to `@unclassified` here is NOT one of the options. That ledger is frozen
             debt from 2026-07-28 and only shrinks.
             """
    end

    test "a rule that got classified has left the ledger", %{flagged: flagged} do
      graduated = Enum.sort(@unclassified -- flagged)

      assert graduated == [],
             """

             #{length(graduated)} rule(s) are on the @unclassified ledger but the scan no longer
             flags them:

             #{Enum.map_join(graduated, "\n", &"    #{&1}")}

             Remove them from @unclassified in this file. That is what makes the ledger shrink and
             what makes the paydown permanent — off the ledger, the rule can never go back to
             unclassified without a deliberate re-freeze.
             """
    end
  end
end
