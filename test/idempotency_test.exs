defmodule Credence.IdempotencyTest do
  # `async: false`: each case runs the full `Credence.fix/1` pipeline twice.
  use ExUnit.Case, async: false

  alias Credence.Idempotency

  @moduledoc """
  docs/22 T2.5 / docs/12 C7 — `fix/1` over its own output.

  Measured over all 5,188 unique fix-test fixtures: 2,158 change on pass 1 and
  **32** are not stable after it (29 when first measured 2026-07-28; three added
  2026-08-17 when the Pattern round stopped skipping non-compiling files — see the
  note above `@ledger`). Most are cascades working as docs/14 E7 intends, so
  today's 32 are frozen and the DELTA is gated — the C13/C14 shape. A flat "must
  be idempotent" assertion would be red for correct behaviour, and a gate that is
  red for correct behaviour gets disabled.

  Two halves, deliberately:

    * the **stale-entry** check runs by default and is fast (32 fixtures). It
      stops the ledger rotting: pay one down and this goes red until you delete
      the row.
    * the **no-new-entries** check is the full ~10-minute sweep. It is tagged
      `:idempotency` and **runs by default** — the tag is an escape hatch, not an
      exclusion, because a layer nobody runs is not a gate:

          mix test                              # everything, ~19 min
          mix test --exclude idempotency        # the fast local loop
          mix test --only idempotency           # just the sweep

      It can also be SCOPED, which is what the evolution harness's Gate wants —
      it runs the clone's whole suite once per candidate rule, and sweeping all
      ~5,200 fixtures to judge one new rule costs ~9 minutes per candidate to
      answer a question about other rules:

          CREDENCE_IDEMPOTENCY_ONLY=no_manual_max mix test --only idempotency

  The sweep is what found T3.12 — a rule renaming `__MODULE` toward the alias
  `MODULE`, producing code that compiles clean and raises at runtime. No parse
  check and no compile check can see that.
  """

  # Frozen 2026-07-28. May only SHRINK — with one recorded exception, below.
  #
  # ## Why this grew from 29 to 32 on 2026-08-17, and why that is not a breach
  #
  # "May only shrink" is the right rule for a ratchet over RULES: a new row means
  # a rule regressed. It is the wrong rule when the ENGINE changes underneath the
  # measurement, and that is what happened here.
  #
  # The Pattern round used to skip any file that did not compile. That gate came
  # off (`lib/pattern.ex:85-99`, replaced by the relative
  # `RuleHelpers.compiles_no_worse?/2` oracle), on measured grounds: 625 of 1,724
  # Pattern fixtures parse but do not compile, and 275 now get a repair they never
  # got. All three fixtures added below have `compiles?/1 == false`, so before that
  # change the Pattern round did nothing to them and they were fixpoints by
  # exclusion rather than by convergence. The rows are the price of that repair
  # coverage, not evidence of a defect.
  #
  # Each was traced pass by pass, and all three converge after exactly two changes
  # with no oscillation:
  #
  #   * `no_keyword_get_with_atom_first_arg` — Pattern repairs the call and leaves
  #     `clock` unused, so `Semantic.UnusedVariable` renames it to `_clock` on
  #     pass 2. Verbatim the docs/14 E7 class this ledger's moduledoc already
  #     describes as "cascades working as intended".
  #   * `no_literal_list_typespec` — the same shape (`numbers` -> `_numbers`) after
  #     the `[a, b]` -> `{a, b}` typespec repair.
  #   * `prefer_map_new_with_transform` — a genuine two-rule Pattern cascade:
  #     `PreferMapNewWithTransform` collapses the `Enum.map |> Map.new`, then
  #     `NoGroupByForFrequencies` collapses the result to
  #     `Enum.frequencies_by(rows, fn r -> r.id end)`. The final form is correct
  #     and is a fixpoint.
  #
  # This also exposed a gap worth keeping in view: the sweep is `:idempotency`,
  # excluded from the default suite, so nothing catches a regression in it between
  # deliberate runs. These three sat undetected since the compile gate came off.
  # The last recorded green sweep is STATUS.md A4 at `00c1c1c`, when the suite was
  # 10,023 tests; it is 10,245 now.
  @ledger [
    # 28 entries
    {"test/pattern/no_keyword_get_with_atom_first_arg_fix_test.exs", "6c808844672f"},
    {"test/pattern/no_length_guard_to_pattern_fix_test.exs", "0c39b6dd92a2"},
    {"test/pattern/no_length_guard_to_pattern_fix_test.exs", "8873e59a9634"},
    {"test/pattern/no_length_guard_to_pattern_fix_test.exs", "f6b660297f03"},
    {"test/pattern/no_literal_list_typespec_fix_test.exs", "ba8980e4c64f"},
    {"test/pattern/no_map_update_then_fetch_fix_test.exs", "45d612866893"},
    {"test/pattern/no_map_update_then_fetch_fix_test.exs", "ba640e7aca16"},
    {"test/pattern/no_map_update_then_fetch_fix_test.exs", "d423f8fd8be4"},
    {"test/pattern/no_map_update_then_fetch_fix_test.exs", "e462684d8ec4"},
    {"test/pattern/no_redundant_negated_guard_fix_test.exs", "1c5d357f1d44"},
    {"test/pattern/no_redundant_negated_guard_fix_test.exs", "759b3bc0852d"},
    {"test/pattern/no_redundant_negated_guard_fix_test.exs", "b410a15a3e1b"},
    {"test/pattern/no_redundant_negated_guard_fix_test.exs", "dc8ea8c5c493"},
    {"test/pattern/no_redundant_negated_guard_fix_test.exs", "f5b59e904480"},
    {"test/pattern/no_redundant_underscore_bind_fix_test.exs", "d2a7227306c8"},
    {"test/pattern/no_string_concat_in_loop_fix_test.exs", "ce26b9fb7ce6"},
    {"test/pattern/no_take_while_length_check_fix_test.exs", "5124427b868b"},
    {"test/pattern/no_take_while_length_check_fix_test.exs", "695830156127"},
    {"test/pattern/no_take_while_length_check_fix_test.exs", "cbc22ec9a60f"},
    {"test/pattern/no_take_while_length_check_fix_test.exs", "fe615c683c23"},
    {"test/pattern/prefer_guard_over_if_fix_test.exs", "39cba6c265a4"},
    {"test/pattern/prefer_guard_over_if_fix_test.exs", "e6a43b35c436"},
    {"test/pattern/prefer_map_new_with_transform_fix_test.exs", "ab55cd841743"},
    {"test/semantic/fix_jason_decode_error_message_field_fix_test.exs", "a8853f8a62a6"},
    {"test/semantic/fix_task_id_field_access_fix_test.exs", "e110fad06ccc"},
    {"test/semantic/no_stream_data_tuple_with_list_fix_test.exs", "51533eecd562"},
    {"test/semantic/no_stream_data_tuple_with_list_fix_test.exs", "585fbd525b2e"},
    {"test/semantic/no_unreachable_case_clause_by_type_fix_test.exs", "038c9c65edc8"}
  ]

  describe "the ledger only shrinks" do
    test "every ledgered fixture is still non-idempotent" do
      by_file = Enum.group_by(@ledger, &elem(&1, 0), &elem(&1, 1))

      paid_down =
        Enum.flat_map(by_file, fn {file, hashes} ->
          fixtures = Idempotency.fixtures_of(file)

          Enum.flat_map(hashes, fn hash ->
            case Map.fetch(fixtures, hash) do
              :error -> ["#{file} #{hash} — fixture no longer exists"]
              {:ok, src} -> if Idempotency.non_idempotent?(src), do: [], else: ["#{file} #{hash}"]
            end
          end)
        end)

      assert paid_down == [],
             """
             These fixtures reach a fixpoint now, so they are no longer debt —
             delete their rows from @ledger.

             A ratchet that keeps paid entries stops being a ratchet: the row
             would sit there granting permission for a regression to slide back
             in under it.

             #{Enum.join(paid_down, "\n")}
             """
    end

    test "the ledger has no duplicate rows" do
      assert Enum.uniq(@ledger) == @ledger
    end
  end

  # The machinery, pinned independently of the ledger's contents — the T3.10a
  # lesson. When the ledger reaches zero these still hold, so "nobody is
  # non-idempotent" and "the detector stopped working" stay distinguishable.
  describe "the detector works regardless of what the ledger says" do
    test "source no rule touches is a fixpoint" do
      refute Idempotency.non_idempotent?("defmodule Stable do\n  def a, do: 1\nend\n")
    end

    test "a known non-idempotent fixture is detected" do
      # From the ledger itself: a Pattern fix that leaves a variable the Semantic
      # round then reports as unused.
      {file, hash} = hd(@ledger)
      src = Map.fetch!(Idempotency.fixtures_of(file), hash)

      assert Idempotency.non_idempotent?(src)
    end

    test "fixtures are extractable at all" do
      # If extraction silently returned nothing, every check above would pass
      # over an empty set and assert nothing.
      counts = Enum.map(Idempotency.files(), &map_size(Idempotency.fixtures_of(&1)))

      assert length(counts) > 250
      assert Enum.sum(counts) > 4_000
    end
  end

  # The scope the harness Gate uses. Untagged, because it is milliseconds and it
  # guards the sweep against the two ways a filter goes wrong: matching nothing
  # (a gate that passes by having no work) and matching everything (no saving).
  describe "sweep scope" do
    test "an unset scope sweeps every fix-test file" do
      assert Idempotency.files(nil) == Idempotency.files([])
      assert length(Idempotency.files(nil)) > 100, "the unscoped sweep must still be the sweep"
    end

    test "a named rule narrows to exactly its own fix test" do
      scoped = Idempotency.files(["no_manual_max"])

      assert length(scoped) == 1
      assert Path.basename(hd(scoped)) == "no_manual_max_fix_test.exs"
      assert scoped != Idempotency.files(nil), "scoping that changes nothing saves nothing"
    end

    test "several rules narrow to several files" do
      scoped = Idempotency.files(["no_manual_max", "no_manual_min"])
      assert length(scoped) == 2
    end

    # A name nobody has is the dangerous case: it must be visibly empty, not
    # silently the whole suite.
    test "an unknown rule narrows to nothing rather than to everything" do
      assert Idempotency.files(["no_such_rule_exists"]) == []
    end

    test "the environment is parsed as a comma-separated list" do
      System.put_env("CREDENCE_IDEMPOTENCY_ONLY", " a , b ")
      assert Idempotency.scope_from_env() == ["a", "b"]

      System.put_env("CREDENCE_IDEMPOTENCY_ONLY", "")
      assert Idempotency.scope_from_env() == nil
    after
      System.delete_env("CREDENCE_IDEMPOTENCY_ONLY")
    end
  end

  @tag :idempotency
  @tag timeout: 900_000
  test "no fixture outside the ledger is non-idempotent" do
    ledgered = MapSet.new(@ledger)

    offenders =
      Idempotency.scope_from_env()
      |> Idempotency.files()
      |> Enum.flat_map(fn file ->
        file
        |> Idempotency.fixtures_of()
        |> Enum.filter(fn {_hash, src} -> Idempotency.non_idempotent?(src) end)
        |> Enum.map(fn {hash, _src} -> {file, hash} end)
      end)
      |> Enum.reject(&MapSet.member?(ledgered, &1))

    assert offenders == [],
           """
           New non-idempotent fixtures. `fix/1` over its own output changed it
           again, which is either a rule walking toward its answer one step per
           pass (T3.12's shape — check whether the intermediate output is even
           valid) or a genuine cascade.

           Decide which, then either fix the rule or add the row to @ledger with
           a reason.

           #{Enum.map_join(offenders, "\n", fn {f, h} -> "  " <> inspect({f, h}) <> "," end)}
           """
  end
end
