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
    * **A trap that is unconstructible is not demanded.** Class 1 skips a test
      whose inputs contain no number, class 2 one whose inputs contain no string.
      `PreferMapsetForSetEquality` sorts `String.codepoints/1` output — binaries
      only — and its own moduledoc shows the int/float divergence is excluded *by
      construction*; demanding a numeric tie of it would be unsatisfiable.
    * **A rule that declares `:single_codepoint_graphemes` is exempt from class
      2.** It has narrowed its own domain and the engine already filters it out
      under `:strict`; testing it outside that domain is a bonus, never a duty.

  Finally, a test whose `inputs:` expression cannot be evaluated standalone is
  **not judged** — the gate declines rather than guesses. All 155 rules evaluate
  today (module attributes and the `EquivalenceInputs` alias are resolved first);
  a test that binds its inputs to test-local state would slip past, which is the
  one known way to dodge this gate.

  ## Live population when this landed

  155 Pattern rules · 21 opt-out marks (not judged) · class 1: 15 subjects, 5 of
  them skipped as number-free · class 2: 13 subjects, 3 of them exempt by
  assumption. Two rules were flagged, both genuinely:
  `NoNestedEnumOnSameEnumerable` (a satisfiable coverage gap — the ties pass) and
  `PreferMapIntersectOverMapsetIntersection`, whose `Enum.sort_by(key)` emission
  was a **live behaviour change** on tie keys and was repaired in the same change.
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
            Map.merge(base, unjudgeable())
        end

      :error ->
        Map.merge(base, unjudgeable())
    end
  end

  # Not judged: an opt-out mark, a missing file (test 1 of `EquivalenceMetaTest`
  # owns that), or inputs that cannot be evaluated standalone.
  defp unjudgeable do
    %{
      judgeable: false,
      inputs: [],
      has_number: false,
      has_string: false,
      has_tie: false,
      has_multi_codepoint: false
    }
  end

  test "1. every value-kind-sensitive rule is tested on inputs that carry the `1` vs `1.0` trap" do
    bad =
      analyze_all()
      |> Enum.filter(fn a -> a.judgeable and a.value_kind_class and a.has_number end)
      |> Enum.reject(fn a -> a.has_tie end)

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
    bad =
      analyze_all()
      |> Enum.filter(fn a ->
        a.judgeable and a.grapheme_class and a.has_string and not a.declares_single_codepoint
      end)
      |> Enum.reject(fn a -> a.has_multi_codepoint end)

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
