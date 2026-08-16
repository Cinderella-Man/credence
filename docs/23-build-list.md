# 23 — The build list, measured

> **This supersedes docs/17's ranked build list**, which docs/18 §5.3 records as
> having "taken heavy damage on review". docs/22 T5.8 asked for the honest
> replacement. This is it.

**Status:** measured 2026-08-16 · **Method:** every candidate's target was run
through the live pipeline, not read.

docs/18 dispositioned the 143 rejected rules. Two dispositions describe work
that might still be worth doing — `rebuild-later-from-catalogue` (16) and
`salvage-small-fix` (9), **25 candidates**. The other 118 are deletions.

The list below is what remains after checking each against the live tree by
**running its target through `Credence.fix/2`**. That check moved eight
candidates off the list, and the reason it could is that the honest repair for
most of them was never a new rule — it was a row in
`Semantic.UndefinedFunction`'s replacement tables.

## Repaired today — no rule needed (11)

(Plus two that DID need a rule and now have one: `no_deprecated_not_in` and
`no_pipe_into_unary_arithmetic`. The latter was listed as
`no_pipe_into_arithmetic_operator`; the name narrowed because only `+` and `-`
reach the Semantic round — `|> * 2` and `|> / 2` are syntax errors and would be
a Syntax rule.)

| candidate | how |
|---|---|
| `no_exit_two_args` | `{"exit", 2}` local row → `Process.exit/2`, with an arity check |
| `no_list_keystore_three_args` | `{:insert_arg, …}`, a new positional-insert verb |
| `no_hallucinated_base_hex_encode` | `Base.hex_encode/1,2` → `encode16`, `hex_encode64` → `encode64` |
| `no_hallucinated_crypto_hex` | `:crypto.hex/1` → `Base.encode16` |
| `no_hallucinated_erlang_warn` | `:erlang.warn/1` → `IO.warn` |
| `no_hallucinated_queue_empty` | `:queue.empty/0` → `new`; **/1 → `is_empty`**, added here |
| `fix_hallucinated_naive_datetime_accessor` | shipped (ledger row 458) |
| `no_agent_update_tuple_wrapper` | **deliberately not built** — docs/17 entry 28 |
| `no_hallucinated_map_reduce` | `Map.reduce/3` → `Enum.reduce/3` |
| `no_hallucinated_stream_data_string` | `StreamData.string/0` → `string(:ascii)` |
| `no_hallucinated_crypto_compare` | `:crypto.compare/2` → `:crypto.hash_equals/2` |

`no_agent_update_tuple_wrapper` is the one that matters most. It was built,
tested green, and deleted the same day: its "before" returns a valid value on
every input, so the rewrite silently breaks any code that reads the tuple. The
failure mode is real and catalogued; the rule cannot exist.

## Still unbuilt, and each verified still uncovered (12)

Every one was confirmed uncovered by running its target: the pipeline returns the
source unchanged today.

**No table rows remain** — the three this list identified as cheapest were added
the same day. Everything below needs a rule and its own equivalence argument:

* `no_enum_sort_then_map_values`
* `no_raw_send_in_genserver_handle_call`
* `no_genserver_reply_in_handle_call` — the failure mode is severe (the caller
  EXITs `:timeout` holding a stray `{:reply, _}` that can corrupt a later
  `receive`), and its detection logic is already correct; only its trigger was
  a fabricated diagnostic, so this is a phase move, not a rebuild
* `no_stream_data_constant_with_range`
* `fix_ets_new_string_name`, `fix_ets_options_bare_keypos`
* `no_process_send_after_infinity` — needs a safety switch, not a narrowing
* `no_atom_as_function_name`, `fix_stray_comma_before_when_guard`,
  `fix_when_guard_in_for_comprehension` — Syntax, and the last two must be built
  **together** sharing one backward lexer-aware scanner, because they emit the
  byte-identical error and need opposite repairs
* `fix_undefined_struct_in_pattern`, `fix_undefined_type_t_in_spec`,
  `fix_mixed_required_optional_map_keys`
* `no_remote_function_in_guard` — **read docs/17 entry 11 first**: it has three
  recorded corruption paths, including output that does not parse

## What is NOT on this list

The 56 banked observations stay banked; they are failure modes without a
proposed rule and belong in docs/17, not here. The "2 lines to widen" and "4
shipped bugs" halves of docs/17's original list both landed weeks ago.
