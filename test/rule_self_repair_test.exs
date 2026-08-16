defmodule Credence.RuleSelfRepairTest do
  @moduledoc """
  Gate: every Pattern rule's own documented anti-pattern is actually repaired by
  the pipeline — not by calling the rule directly, but by running the round the
  way a user does.

  ## Why this is a different question from "the rule has a fix"

  `rule_card_test.exs` proves each `## Bad` example makes its own rule fire, and
  the per-rule fix tests prove `fix_patches/2` produces the right output. Neither
  proves the two meet. A rule can pass both and still repair nothing in practice:
  its patches can be discarded by the safety invariants, or its output can be
  reverted for adding a compile error, and the only trace is a `Logger.warning`
  nobody reads.

  Measured when this gate was written: **six of 156 rules could not repair their
  own documented example end-to-end** — three `:reverted`, three
  `:patch_rejected`. All six turned out to be defects in the *examples* rather
  than the rules; every one was a bare snippet rather than a module, and

    * `Agent.get_and_modify(__MODULE__, ...)` at the top level **executes** during
      the compile check and exits with `:noproc`, so before and after differed by
      an incidental error message;
    * `defp helper(x)` outside a module traded "cannot invoke `@doc`/1 outside
      module" for "cannot invoke `defp`/2 outside module" — a different error, so
      correctly rejected;
    * `[h | t] ->` with only `# ... complex body` under it is not valid Elixir.

  Wrapped in modules, all six repair cleanly. That is the point of the gate: the
  examples are also the D8a duplicate corpus and the `rule_card` fixtures, so an
  unrealistic one degrades three things at once, and nothing else was checking.
  """
  use ExUnit.Case, async: true

  alias Credence.RuleDuplication

  # Rules whose Bad example is repaired by a DIFFERENT rule reaching it first.
  # This is the Pattern round working as designed — it is a cascade, and the
  # earlier rule leaves nothing for the later one to match. Ledgered rather than
  # waved through so that a rule going dark for any other reason still fails.
  @cascade %{
    # Both reach `String.length/1`; pinned in graphemes_count_family_test.exs
    # and ledgered as an overlapping-not-duplicate pair in D8a.
    Credence.Pattern.NoEnumCountForLength => Credence.Pattern.AvoidGraphemesEnumCount,
    Credence.Pattern.PreferGraphemesForCharacterUniqueness =>
      Credence.Pattern.NoEnumCountForLength,
    Credence.Pattern.PreferMultiClauseReduceFn => Credence.Pattern.PreferCondForNestedIf
  }

  describe "the documented anti-pattern does not survive the pipeline" do
    test "every Pattern rule's `## Bad` example is repaired end-to-end" do
      rules = Credence.MetaTestSupport.rules()

      outcomes =
        for rule <- rules,
            bad = RuleDuplication.bad_example(rule),
            bad not in [nil, ""] do
          {code, applied} = Credence.Pattern.fix_with_trace(bad)

          status =
            case List.keyfind(applied, rule, 0) do
              {^rule, count} when is_integer(count) -> :repaired
              {^rule, other} -> other
              nil -> if code != bad, do: :repaired_by_another, else: :untouched
            end

          {rule, status}
        end

      assert length(outcomes) >= 156,
             "only #{length(outcomes)} rules had an example to run; the extractor has regressed"

      failures =
        for {rule, status} <- outcomes,
            status != :repaired,
            not (status == :repaired_by_another and Map.has_key?(@cascade, rule)),
            do: {rule, status}

      assert failures == [],
             """
             These rules report their own documented anti-pattern but the pipeline
             leaves it unrepaired:

             #{Enum.map_join(failures, "\n", fn {r, s} -> "  #{inspect(r)} -> #{s}" end)}

             `:patch_rejected` means the safety invariants discarded the patches
             (output did not parse, or the comment multiset changed).
             `:reverted` means the output added a compile error the input did not
             have. `:untouched` means the fix ran and changed nothing.

             Check the EXAMPLE first — every instance found so far was a bare
             snippet that no real file would contain, and wrapping it in a module
             fixed it. Only then suspect the rule.
             """
    end

    test "each ledgered cascade is still a cascade, and still by the same rule" do
      stale =
        for {rule, expected} <- @cascade do
          bad = RuleDuplication.bad_example(rule)
          {_code, applied} = Credence.Pattern.fix_with_trace(bad)

          cond do
            List.keyfind(applied, rule, 0) != nil -> {rule, :fires_itself_now}
            List.keyfind(applied, expected, 0) == nil -> {rule, :different_rule_now}
            true -> nil
          end
        end
        |> Enum.reject(&is_nil/1)

      assert stale == [],
             """
             The cascade ledger is out of date — it may only shrink:

             #{Enum.map_join(stale, "\n", fn {r, why} -> "  #{inspect(r)}: #{why}" end)}

             `:fires_itself_now` means the entry is paid down; delete it.
             `:different_rule_now` means the cascade order changed, which is a
             behaviour change worth understanding before re-pointing the entry.
             """
    end
  end

  describe "control" do
    # The gate reads a status out of the applied-rules trace. A trace that
    # reported success for everything would make it vacuous, so: a rule given an
    # input it has nothing to say about must come back `:untouched`.
    test "a rule with nothing to do is not reported as repaired" do
      clean = "defmodule RsrClean do\n  def f(x), do: x\nend\n"

      {code, applied} = Credence.Pattern.fix_with_trace(clean)

      assert code == clean
      assert applied == []
    end
  end
end
