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

## Still unbuilt, and each verified still uncovered (8)

Every one was re-confirmed uncovered on 2026-08-17 by running its target through
`Credence.fix/1`: the pipeline returns the source unchanged. That re-check
mattered — the Pattern round no longer skips files that fail to compile, which
could have covered some of these silently, and one item turned out to be covered
by an existing rule.

**No table rows remain** — the three this list identified as cheapest were added
the same day. Everything below needs a rule and its own equivalence argument:

* ~~`no_enum_sort_then_map_values`~~ **BUILT 2026-08-17** —
  `lib/pattern/no_enum_sort_then_map_values.ex`. Shipped much narrower than the
  catalogue's class, because measuring the class refuted it: `Stream.*` returns
  a **struct** (so `Map.values/1` on it does not raise at all), `Map.new/1` is a
  constructor that *wants* a list, and `Enum.into`/`group_by`/`frequencies`/
  `reduce` return maps while `at`/`find`/`max_by` return an element that usually
  is one. Over the corpus that is 350 candidate sites of the ungated class with
  **zero** true positives. What shipped: `Enum.sort/1,2` or `Enum.sort_by/2,3`
  as the immediate neighbour of `Map.values/1` → `Enum.map(fn {_key, value} ->
  value end)`, which is verbatim the narrowing docs/18's own disposition
  sanctioned. See docs/17 §5.1 for the corrected premise.
* `no_raw_send_in_genserver_handle_call` — **BLOCKED, see the next section**
* `no_genserver_reply_in_handle_call` — **BLOCKED, see the next section.** The
  failure mode is severe (the caller EXITs `:timeout` holding a stray
  `{:reply, _}` that can corrupt a later `receive`) and its detection logic is
  already correct; only its trigger was a fabricated diagnostic. This line used
  to conclude "so this is a phase move, not a rebuild". That is true of the
  detection and beside the point: docs/18 says in as many words **do not port
  this module's fix**, and a rule with detection and no fix does not ship here.
* `no_stream_data_constant_with_range` — **BLOCKED, see the next section**
* `no_process_send_after_infinity` — **BLOCKED, see the next section.** "Needs a
  safety switch, not a narrowing" is still the most promising route, and it is
  the only one of the three with a route at all — but `assumptions/0` is a
  mechanism with two switches today, so adding one is its own justification.
* `no_atom_as_function_name`, `fix_stray_comma_before_when_guard`,
  `fix_when_guard_in_for_comprehension` — Syntax, and the last two must be built
  **together** sharing one backward lexer-aware scanner, because they emit the
  byte-identical error and need opposite repairs
* `fix_undefined_struct_in_pattern`, `fix_mixed_required_optional_map_keys`

  (`fix_undefined_type_t_in_spec` is **covered**, re-verified 2026-08-17 — but by
  a different reading than this list assumed. `NoBareNamesInSpec` rewrites
  `@spec f(t) :: :ok` to `@spec f(t :: any())`, treating the bare name as a
  parameter LABEL rather than as a reference to the type `t()`. Both are valid
  readings of what the author meant; the output compiles, so the item is closed
  rather than pending a second interpretation.)
* `no_remote_function_in_guard` — **read docs/17 entry 11 first**: it has three
  recorded corruption paths, including output that does not parse

## ⚠️ Three of the eight are blocked on one policy question, not on effort

Recorded 2026-08-17, from re-reading `docs/18-per-rule-verdicts.json`'s `action`
field for every remaining item. **Four of the eleven remaining rule names —
spanning three of the eight items — are specified *report-only* by their own
dispositions**, and this project deletes report-only rules (CONTEXT.md: "every
rule either fixes its problem or it doesn't exist"). As specified they cannot be
built at all — that is a different status from "not built yet", and the list did
not distinguish them. (The two GenServer rules are one item; they are the same
cluster and docs/17 entry 3 unions them.)

| item | what docs/18 actually says |
|---|---|
| `no_raw_send_in_genserver_handle_call` | "report only, **emit no fix** — pattern has no compiler oracle, and the executed probe shows the naive `= from` repair silently clobbers an existing `from` binding and still ships compiling-but-broken code" |
| `no_genserver_reply_in_handle_call` | "report only, **do not port this module's fix** (proof in evidence item 4)" |
| `no_process_send_after_infinity` | "file ONE new **REPORT-ONLY** pattern-phase rule … carry over NO code from this fossil — its clause-splitting fix is proven to dead-code sibling clauses" |
| `no_stream_data_constant_with_range` | "record the failure mode … as **REAL-but-not-catchable in the current architecture** — semantic cannot see it (zero diagnostics) and pattern forbids report-only rules while the `constant`→`member_of` rewrite is an unrevertable behaviour change on legitimate `constant(1..10)` code" |

Two of this list's own annotations understate that. `no_genserver_reply_in_handle_call`
is described above as "a phase move, not a rebuild". That is true of the
*detection* and beside the point: a rule with detection and no fix does not ship
here, and its disposition says **do not port this module's fix** in as many
words. The phrase also invites the one disposition docs/18 explicitly banned —
docs/18 §"What this pass revised" (line ~1570): *"Audit 2 — 'rehome 18 to
pattern.' **Overturned 17 of 17 tested** … semantic gets the compiler as a free
correctness oracle … while pattern's only net is `apply_or_revert`, which reverts
**solely on compile failure**. Broken-but-compiling output ships. Consequence:
rehome the existing fix was banned as a disposition and appears **0 times in
143**."* (The same pass rates its own rescue accuracy at 6/38 — 32 of 38 rescues
did not survive execution, so the prior on "this one is cheap" is poor.)

Building a *new* pattern rule from the catalogue is not the banned move, and it
is what the disposition actually asks for. The problem is what that rule may do
once it fires: nothing in the Pattern phase can supply the correctness argument,
and the recorded counterexample is this exact cluster — not every `send` to the
caller pid is a reply, since a chunked-stream `handle_call` sends chunks and
replies at the end, so the rewrite turns `{:done, 3}` into `{:chunk, 1}`.

## ✅ DECIDED 2026-08-17 — report-only is closed, so these three are dead as specified

The maintainer settled it: *"if rules can't fix the code they need to be removed.
Try to check can you improve them; if yes go ahead, if not, remove them. WE DO NOT
HAVE 'warn only' rules — Credence is FIXING code, not just complaining about
it."* `STATUS.md` D10 is decided the same way and is now **gated** by
`test/fix_or_drop_test.exs`: no rule may report a finding nothing repairs.

So the three items above cannot be built **as their dispositions specify**, and
that is the end of them as build-list entries rather than a thing to revisit:

| item | disposition | status |
|---|---|---|
| GenServer reply protocol (2 rules) | report-only; "emit no fix"; the repair is verified unsound (a chunked-stream `handle_call` sends chunks then replies, so the rewrite turns `{:done, 3}` into `{:chunk, 1}`) | **dead as specified** |
| `no_stream_data_constant_with_range` | already recorded "REAL-but-not-catchable in the current architecture" | **dead as specified** |
| `no_process_send_after_infinity` | report-only — *but* has one route left | **open, needs a mechanism decision** |

Their failure modes stay banked in `docs/17`, which is the right vessel for a
verified observation with no shippable repair. That is not a downgrade: docs/17
already holds 56 such observations, and the whole point of the catalogue is that
the observation is the asset and the rule module is a fossil.

**`no_process_send_after_infinity` is the one with a way forward**, and it is a
mechanism question rather than a rule question: a fix gated behind an
`assumptions/0` safety switch is neither report-only nor unconditional, because
the engine only runs a rule when all its named assumptions are on
(`RuleHelpers.filter_by_assumptions/3`). `lib/assumptions.ex` carries exactly two
switches today (`:single_codepoint_graphemes`, `:proper_lists`), and adding a
third needs its own justification plus the property test
`test/assumptions_meta_test.exs` requires of any rule with a non-empty
`assumptions/0`. Worth doing only if the repair itself is sound — and docs/18
records the existing clause-splitting fix as "proven to dead-code sibling
clauses", so it would be a fresh build, not a salvage.

`no_process_send_after_infinity` has one possible route that does not need the
policy resolved: `assumptions/0`. A fix gated behind a safety switch is neither
report-only nor unconditional. That is a mechanism change (`lib/assumptions.ex`
carries exactly two switches today) and needs its own justification, but it is
the only third option any of the four has.

**So the honest count is 5 workable + 2 dead + 1 needing a mechanism decision**,
not 8 remaining — and one of the five is not a rule build at all. Workable:

* `no_atom_as_function_name` — Syntax, re-author around the parser's own error
  position rather than a regex.
* `fix_stray_comma_before_when_guard` + `fix_when_guard_in_for_comprehension` —
  one item, both gated on `Code.string_to_quoted(source, columns: true)`
  returning the same `'when'` error, which is exactly why they share a scanner.
* `fix_mixed_required_optional_map_keys` — Syntax, built as a sibling of the live
  `Credence.Syntax.FixKeywordBeforePositionalArgument`.
* `no_remote_function_in_guard` — keep only the pattern-move repair; docs/18
  names the exact functions to delete, and docs/17 entry 11 the three corruption
  paths.
* `fix_undefined_struct_in_pattern` — **not a new rule.** Its disposition
  redirects it to extending the live
  `Credence.Semantic.FixCyclicStructReference` to hoist struct-defining nested
  modules above their first reference, keeping that rule's existing
  compile-verifying `confirm_reorder/2` gate.

## What is NOT on this list

The 56 banked observations stay banked; they are failure modes without a
proposed rule and belong in docs/17, not here. The "2 lines to widen" and "4
shipped bugs" halves of docs/17's original list both landed weeks ago.
