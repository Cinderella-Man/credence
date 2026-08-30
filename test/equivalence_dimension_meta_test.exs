defmodule Credence.EquivalenceDimensionMetaTest do
  @moduledoc """
  C2.2 — the gate that a rule's equivalence test uses the dimension its risk
  actually lives in.

  `EquivalenceMetaTest` proves a rule *has* a real equivalence test. This proves
  the test's **inputs** can see the divergence the rule's own operation class can
  produce. A rule that rewrites an ordering and is tested only on all-distinct
  integers has a green equivalence suite that proves nothing — docs/14 E1 is the
  shipped instance: `term_lists`' only mixed-kind entry tied at the *minimum*, so
  first-vs-last-maximal divergence was invisible and two live bugs went out
  through a green suite. Authors (human and LLM alike) pick the generator that
  names their concern, not the one that carries the trap.

  Two classes. Each has a mechanical trigger read off the **rule** source and a
  requirement checked against the **test's actual `inputs:` values** — evaluated,
  not named, so a hand-rolled list counts exactly as much as an
  `EquivalenceInputs` dimension:

    1. **Value-kind.** The rule matches or emits an order- or identity-sensitive
       collection call (`Enum.sort`/`sort_by`, `min`/`max`(`_by`), `uniq`,
       `dedup`, `frequencies`, `group_by`, `member?`). Erlang term order compares
       `1` and `1.0` **equal** — so a sort ties them — while every map / `MapSet`
       / `===` path treats them as **distinct**. That single pair is the trap, so
       the inputs must contain an integer and a float that are `==` inside the
       *same* input.

    2. **Grapheme domain.** The rule matches or emits a `String` grapheme /
       codepoint call *and does not declare the `:single_codepoint_graphemes`
       assumption* — i.e. it claims to be correct for arbitrary Unicode. Then its
       inputs must contain at least one string with a multi-codepoint grapheme
       (decomposed accent, ZWJ emoji, regional-indicator flag). This is not an
       arbitrary "use dimension X": it is the rule's *own declared domain* and
       its test inputs being made to agree.

  ## Where the trigger comes from (and why it is not a grep for "Enum.sort")

  A rule mentions `Enum.sort_by` in its own housekeeping all the time
  (`Enum.sort_by(issues, & &1.line)`); a plain text scan flags 13 rules that have
  nothing to do with sorting user code. The trigger instead reads only
  `__aliases__` **literals** — `{:__aliases__, _, [:Enum]}, :sort]` — which occur
  exclusively in a quoted pattern the rule *matches* or a quoted node it *emits*.
  See `MetaTestSupport.rule_stdlib_callees/1`.

  ## Deliberate non-flags — this gate is narrow on purpose

  A false "you must use dimension X" that the author cannot satisfy is worse than
  a gap, so three exemptions are built in:

    * **An `mark_equivalence_*` opt-out is exempt** — there is no input set to
      judge (all three `Keyword.get/2` repair rules land here).
    * **A value-kind trap that is unconstructible is not demanded.** The audited
      `@value_kind_unconstructible` set names rules whose matched pipeline itself
      produces strings. This exemption comes from the rule's admitted domain,
      never from an author's chosen test values.
    * **A rule that declares `:single_codepoint_graphemes` is exempt from class
      2.** It has narrowed its own domain and the engine already filters it out
      under `:strict`; testing it outside that domain is a bonus, never a duty.

  Finally, a sensitive test whose `inputs:` expression cannot be evaluated
  standalone fails the relevant gate: declining to judge would let test-local
  state bypass dimension coverage. Module attributes and the
  `EquivalenceInputs` alias are resolved first.

  ## Live population when this landed

  155 Pattern rules · 21 opt-out marks (not judged) · class 1: 15 subjects, 5 of
  them skipped as number-free · class 2: 13 subjects, 3 of them exempt by
  assumption. Two rules were flagged, both genuinely:
  `NoNestedEnumOnSameEnumerable` (a satisfiable coverage gap — the ties pass) and
  `PreferMapIntersectOverMapsetIntersection`, whose `Enum.sort_by(key)` emission
  was a **live behaviour change** on tie keys and was repaired in the same change.

  ## Why the vacuity block exists

  Both gates below are `Enum.filter |> Enum.reject |> assert bad == []`, so an
  empty *subject* population is indistinguishable from full compliance. That is
  not hypothetical here: the trigger comes from `rule_stdlib_callees/1`, a regex
  over whitespace-stripped rule source. If a formatter change, an emission
  rewrite, or a `@scanned_mods` edit stops that regex matching, every class
  population silently drops to zero and both gates pass green forever while
  measuring nothing. The block pins the three populations the gates stand on —
  the analysed set, the judgeable set, and each class's subject set — so that
  collapse is a red test rather than a quiet one. (C13/C14 shipped with this
  guard; C2.2 landed without it, which is what this closes.)
  """
  use ExUnit.Case, async: true

  # These gates parse every rule module and every rule test file on each run, so
  # they are I/O- and CPU-bound in a way an ordinary unit test is not. Under a
  # full `mix test` the ~20k-file corpus scan runs alongside them and starves
  # them enough to blow the 60s default — observed as a spurious
  # `ExUnit.TimeoutError` in `Credence.SemanticMetaTest`, which passes in 106s
  # for the whole module when run alone. The gate is not slow because anything
  # is wrong; it is slow because it reads the tree.
  @moduletag timeout: :timer.minutes(10)

  import Credence.MetaTestSupport

  @value_kind_unconstructible MapSet.new([
                                Credence.Pattern.PreferCountsForLength,
                                Credence.Pattern.PreferFrequenciesOverGroupBy,
                                Credence.Pattern.PreferGraphemesForCharacterUniqueness,
                                Credence.Pattern.PreferMapsetForSetEquality
                              ])

  @expected_populations %{
    value_kind:
      MapSet.new([
        Credence.Pattern.NoDoubleSortSameList,
        Credence.Pattern.NoEnumTakeNegative,
        Credence.Pattern.NoGroupByForFrequencies,
        Credence.Pattern.NoIfEmptyForEnumMinMax,
        Credence.Pattern.NoNestedEnumOnSameEnumerable,
        Credence.Pattern.NoReduceForGroupBy,
        Credence.Pattern.NoSortForTopK,
        Credence.Pattern.NoSortThenAt,
        Credence.Pattern.NoSortThenReverse,
        Credence.Pattern.PreferDescSortOverNegativeTake,
        Credence.Pattern.PreferMapIntersectOverMapsetIntersection,
        Credence.Pattern.NoChunkByIdentityForDedup
      ]),
    grapheme:
      MapSet.new([
        Credence.Pattern.AvoidGraphemesEnumCount,
        Credence.Pattern.AvoidGraphemesLength,
        Credence.Pattern.NoGraphemePalindrome,
        Credence.Pattern.NoManualStringReverse,
        Credence.Pattern.NoNegativeStepInStringSlice,
        Credence.Pattern.NoStringLengthForCharCheck,
        Credence.Pattern.NoStringLengthForEmptyCheck,
        Credence.Pattern.PreferCountsForLength,
        Credence.Pattern.PreferMapsetForSetEquality,
        Credence.Pattern.PreferStringSliceForTrimLastChar,
        Credence.Pattern.UnnecessaryGraphemeChunking
      ])
  }

  # The predicates (`rule_stdlib_callees/1`, `value_kind_tie?/1`,
  # `multi_codepoint_grapheme?/1`, …) live in `Credence.MetaTestSupport` next to
  # the ones the sibling gates use, so one place defines what the project means
  # by "this rule's operation class".

  # Inspect each rule's source + its equivalence test and report the class it
  # falls in and whether its inputs carry that class's trap.
  defp analyze_all, do: Enum.map(rules(), &analyze/1)

  defp analyze(rule) do
    path = test_path(rule, "equivalence")

    # A rule with no file at its conventional path is `RuleTestCompletenessTest`'s
    # business, not this gate's — classify it as belonging to no class.
    callees =
      case File.read(rule_path(rule)) do
        {:ok, source} -> rule_stdlib_callees(source)
        {:error, _} -> MapSet.new()
      end

    base = %{
      rule: rule,
      path: path,
      value_kind_class: value_kind_sensitive?(callees),
      grapheme_class: grapheme_sensitive?(callees),
      value_kind_unconstructible: rule in @value_kind_unconstructible,
      declares_single_codepoint: :single_codepoint_graphemes in rule.assumptions()
    }

    case load_ast(path) do
      {:ok, ast} ->
        marked = calls_any?(ast, mark_fns())

        case equivalence_input_values(ast) do
          {:ok, inputs} ->
            Map.merge(base, %{
              judgeable: not marked,
              inputs: inputs,
              has_number: any_number?(inputs),
              has_string: any_string?(inputs),
              has_tie: value_kind_tie?(inputs),
              has_multi_codepoint: multi_codepoint_grapheme?(inputs)
            })

          :error ->
            Map.merge(base, unjudgeable(marked))
        end

      :error ->
        Map.merge(base, unjudgeable(true))
    end
  end

  # Not judged: an opt-out mark, a missing file (test 1 of `EquivalenceMetaTest`
  # owns that), or inputs that cannot be evaluated standalone.
  defp unjudgeable(marked) do
    %{
      judgeable: not marked,
      inputs: [],
      has_number: false,
      has_string: false,
      has_tie: false,
      has_multi_codepoint: false
    }
  end

  # The subject sets the two gates below actually filter over. Named here so the
  # vacuity block and the gates cannot drift apart: each gate is exactly
  # `subjects |> Enum.reject(carries_the_trap)`.
  defp class1_subjects(all),
    do:
      Enum.filter(all, fn a ->
        a.judgeable and a.value_kind_class and not a.value_kind_unconstructible
      end)

  defp class2_subjects(all) do
    Enum.filter(all, fn a ->
      a.judgeable and a.grapheme_class and not a.declares_single_codepoint
    end)
  end

  # Kept as predicates so the controls themselves can be tested against a
  # deliberately truncated population, rather than only today's healthy tree.
  defp discovery_complete?(discovered, expected),
    do: MapSet.new(discovered) == MapSet.new(expected)

  defp populations_pinned?(actual, expected),
    do: Map.new(actual, fn {class, subjects} -> {class, MapSet.new(subjects)} end) == expected

  defp source_rules do
    "lib/pattern/*.ex"
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      source = File.read!(path)

      case Regex.run(~r/^defmodule (Credence\.Pattern\.[A-Za-z0-9_]+) do/m, source) do
        [_, name] ->
          if name != "Credence.Pattern.Rule" and
               (String.contains?(source, "use Credence.Pattern.Rule") or
                  String.contains?(source, "@behaviour Credence.Pattern.Rule")),
             do: [Module.concat([name])],
             else: []

        nil ->
          []
      end
    end)
  end

  describe "adversarial controls" do
    test "input inspection rejects non-data calls without executing them" do
      path =
        Path.join(System.tmp_dir!(), "credence-meta-input-#{System.unique_integer([:positive])}")

      on_exit(fn -> File.rm(path) end)

      ast = parse("[inputs: File.write!(#{inspect(path)}, \"ran\")]")

      assert equivalence_input_values(ast) == :error
      refute File.exists?(path)
    end

    test "input inspection puts a deadline around evaluation" do
      ast = parse("[inputs: Stream.cycle([1]) |> Enum.to_list()]")
      task = Task.async(fn -> equivalence_input_values(ast) end)

      assert Task.yield(task, 1_200) == {:ok, :error}
    end

    test "an unevaluable sensitive test remains a gate subject" do
      analysis = %{judgeable: true, value_kind_class: true, value_kind_unconstructible: false}
      refute class1_subjects([analysis]) == []
    end

    test "chosen value kinds cannot remove an otherwise applicable rule" do
      analysis = %{judgeable: true, value_kind_class: true, value_kind_unconstructible: false}
      refute class1_subjects([analysis]) == []
    end

    test "chosen string values cannot remove an otherwise applicable rule" do
      analysis = %{
        judgeable: true,
        grapheme_class: true,
        declares_single_codepoint: false
      }

      refute class2_subjects([analysis]) == []
    end

    test "discovery control rejects the same missing rule on both sides" do
      complete = [:one, :two]
      refute discovery_complete?(tl(complete), complete)
    end

    test "population control rejects losing one of several subjects" do
      expected = %{value_kind: MapSet.new([:one, :two]), grapheme: MapSet.new([:three, :four])}
      actual = %{value_kind: [:one], grapheme: [:three]}
      refute populations_pinned?(actual, expected)
    end
  end

  describe "the gate cannot pass vacuously" do
    test "the analysis sees every Pattern rule" do
      live = source_rules()
      seen = Enum.map(analyze_all(), & &1.rule)

      assert discovery_complete?(seen, live),
             "the gate analysed #{length(seen)} rules but the rule source tree has #{length(live)}. " <>
               "Both checks below are over the analysed set, so a discovery that silently " <>
               "returns fewer rules than exist passes while saying nothing."
    end

    test "the judgeable population is non-empty" do
      judgeable = Enum.filter(analyze_all(), & &1.judgeable)

      refute judgeable == [],
             "every rule came back unjudgeable, so both checks below are `[] == []`. Either " <>
               "`equivalence_input_values/1` stopped evaluating any `inputs:` expression, or " <>
               "the equivalence test files moved off `test_path(rule, \"equivalence\")`."
    end

    test "each class has a non-empty subject population" do
      all = analyze_all()

      actual = %{
        value_kind: Enum.map(class1_subjects(all), & &1.rule),
        grapheme: Enum.map(class2_subjects(all), & &1.rule)
      }

      assert populations_pinned?(actual, @expected_populations),
             "the exact value-kind or grapheme subject population changed. Re-derive the " <>
               "trigger and update the pinned set only after reviewing every added or removed rule."
    end
  end

  test "1. every value-kind-sensitive rule is tested on inputs that carry the `1` vs `1.0` trap" do
    bad = analyze_all() |> class1_subjects() |> Enum.reject(fn a -> a.has_tie end)

    assert bad == [],
           "rules that rewrite an order- or identity-sensitive collection call but whose " <>
             "equivalence inputs contain no `==`-but-not-`===` pair (an integer and a float " <>
             "that compare equal, inside the SAME input), so a tie-group reordering or a " <>
             "map-key-identity change is invisible to them:\n" <>
             bullets(bad, fn a ->
               "#{inspect(a.rule)} — #{a.path} (add e.g. `[1, 1.0, 2]`, or use " <>
                 "`EquivalenceInputs.term_lists/0` / `stability_lists/0`)"
             end)
  end

  test "2. every rule claiming full Unicode generality is tested on a multi-codepoint grapheme" do
    bad = analyze_all() |> class2_subjects() |> Enum.reject(fn a -> a.has_multi_codepoint end)

    assert bad == [],
           "rules that rewrite a String grapheme/codepoint call and declare NO " <>
             ":single_codepoint_graphemes assumption — so they promise to be correct for " <>
             "arbitrary Unicode — but whose equivalence inputs are all single-codepoint, so " <>
             "the promise is never exercised:\n" <>
             bullets(bad, fn a ->
               "#{inspect(a.rule)} — #{a.path} (add a decomposed accent / ZWJ emoji / flag, " <>
                 "or use `EquivalenceInputs.multi_codepoint_strings/0`; if the fix is only " <>
                 "correct for single-codepoint graphemes, declare that assumption instead)"
             end)
  end
end
