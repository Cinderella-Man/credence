defmodule Credence.IdempotencyTest do
  # `async: false`: each case runs the full `Credence.fix/1` pipeline twice.
  use ExUnit.Case, async: false

  alias Credence.Idempotency

  @moduledoc """
  docs/22 T2.5 / docs/12 C7 — `fix/1` over its own output.

  Measured over all 5,188 unique fix-test fixtures: 2,158 change on pass 1 and
  **29** are not stable after it. Most are cascades working as docs/14 E7
  intends, so today's 29 are frozen and the DELTA is gated — the C13/C14 shape.
  A flat "must be idempotent" assertion would be red for correct behaviour, and a
  gate that is red for correct behaviour gets disabled.

  Two halves, deliberately:

    * the **stale-entry** check runs by default and is fast (29 fixtures). It
      stops the ledger rotting: pay one down and this goes red until you delete
      the row.
    * the **no-new-entries** check is the full ~10-minute sweep and is tagged
      `:idempotency`, excluded by default:

          MIX_ENV=test mix test --only idempotency

  The sweep is what found T3.12 — a rule renaming `__MODULE` toward the alias
  `MODULE`, producing code that compiles clean and raises at runtime. No parse
  check and no compile check can see that.
  """

  # Frozen 2026-07-28. May only SHRINK.
  @ledger [
    # 29 entries
    {"test/pattern/no_length_guard_to_pattern_fix_test.exs", "0c39b6dd92a2"},
    {"test/pattern/no_length_guard_to_pattern_fix_test.exs", "8873e59a9634"},
    {"test/pattern/no_length_guard_to_pattern_fix_test.exs", "f6b660297f03"},
    {"test/pattern/no_manual_list_reduce_fix_test.exs", "2f7d8966cdc7"},
    {"test/pattern/no_manual_list_reduce_fix_test.exs", "b5289e82a4d1"},
    {"test/pattern/no_manual_list_reduce_fix_test.exs", "da56b6e54a5c"},
    {"test/pattern/no_manual_list_reduce_fix_test.exs", "e59eb318bc93"},
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

  @tag :idempotency
  @tag timeout: 900_000
  test "no fixture outside the ledger is non-idempotent" do
    ledgered = MapSet.new(@ledger)

    offenders =
      Idempotency.files()
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
