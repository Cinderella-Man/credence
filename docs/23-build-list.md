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

## Still unbuilt, and each verified still uncovered (7 → 6, plus 1 new)

Every one was re-confirmed uncovered on 2026-08-17 by running its target through
`Credence.fix/1`: the pipeline returns the source unchanged. That re-check
mattered — the Pattern round no longer skips files that fail to compile, which
could have covered some of these silently, and one item turned out to be covered
by an existing rule.

**No table rows remain** — the three this list identified as cheapest were added
the same day. Everything below needs a rule and its own equivalence argument.

Two items have since been struck (`no_enum_sort_then_map_values`,
`no_atom_as_function_name`) and a third closed by one rule rather than the two it
listed (the `when`-guard pair). Building that pair added `fix_when_guard_in_with_clause`
— a shape docs/18 dispositioned wrongly, whose repair is a move rather than a
deletion. **Two buildable items remain:** `fix_when_guard_in_with_clause` and
`no_remote_function_in_guard`; plus the three blocked on the report-only policy
question and `fix_undefined_struct_in_pattern`, which is an extension to a live
Semantic rule rather than a new rule.

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
* ~~`no_atom_as_function_name`~~ **BUILT 2026-08-17** —
  `lib/syntax/no_atom_as_function_name.ex`. See the note below.
* ~~`fix_stray_comma_before_when_guard`, `fix_when_guard_in_for_comprehension`~~
  **BUILT 2026-08-17 as ONE rule**, `lib/syntax/fix_misplaced_when_guard.ex`, on the
  shared `lib/syntax/when_guard_position.ex`. See the note below.
* `fix_when_guard_in_with_clause` — **NEW, discovered while building the pair.** Not a
  variant of them: the repair is a **move**, not a deletion. See the note below.
* `fix_undefined_struct_in_pattern`
* ~~`fix_mixed_required_optional_map_keys`~~ **BUILT 2026-08-17** —
  `lib/syntax/fix_mixed_required_optional_map_keys.ex`. See the note below.

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

* ~~`no_atom_as_function_name`~~ **BUILT 2026-08-17.** Re-authored around the
  parser's own error position, as the disposition specified — and the payoff is
  larger than "no regex". A rule that acts only where parsing STOPPED cannot touch
  a file that parses, so the whole string/comment/heredoc decoy class is
  *unreachable* rather than merely filtered: measured, `fix/1` alters **0 of ~300**
  files in `lib/`, which answers the self-corruption oracle's question
  structurally. Scope is `\w+` plus an optional trailing `?`/`!`, every boundary
  executed — `:valid?(1)` and `:save!(1)` repair to valid code, `:"my fun"(1)` and
  `:+(1, 2)` do not, so those decline on both sides. Both fixtures are the recorded
  field samples, including `:ets.whereis(:ets_table_name(name))`, where the parser
  reports the inner `(` and so the correct colon is repaired without the rule
  knowing which module names are real.
* ~~`fix_stray_comma_before_when_guard` + `fix_when_guard_in_for_comprehension`~~ —
  **BUILT as one rule, and it had to be.** They do share a scanner
  (`Credence.Syntax.WhenGuardPosition`, on `SourceMask.mask/1` rather than a second
  hand-written lexer), but two *rules* cannot do the job. The Syntax round is a single
  `Enum.reduce` (`lib/syntax.ex:93`) — each `fix/1` runs once — and the parser reports
  only the first error, so on a file whose `for` defect precedes its `def` defect the
  comma rule declines, the `for` rule repairs its own shape and stops, and
  `commit_or_roll_back/4` discards the round. Measured with the two as separate rules:

      def THEN for  ->  parses,       [{FixStrayComma…, 1}, {FixWhenGuard…, 1}]
      for THEN def  ->  parses=false, [{FixWhenGuard…, :rolled_back}]

  No rule order fixes it; reversing moves the failure to the other interleaving. One
  rule converges in one pass, and both interleavings are pinned at round level.

  Three further corrections came out of building it, each executed:

  - **Re-parsing does not discriminate the two shapes.** For `def`, `for`, `with`,
    `case` and `fn`, deleting the comma AND deleting the `when` each yield source that
    parses. Compiling is what separates them, so it derived the mapping; the runtime
    discriminator is structural.
  - **`with` must decline, which corrects docs/18** — see the new item above.
  - **`for`'s repair is not ambiguous after all.** A guard is legal in a generator
    pattern, so "move it left of the `<-`" looked like a second valid repair. Executed,
    the two return identical results on the heterogeneous list proposed as the
    counterexample (a generator pattern already skips what it does not match), and
    delete-the-`when` is strictly more general: a filter may be any expression, so
    `for a <- l, String.length(inspect(a)) > 0` runs where the moved form is a
    `CompileError`.
* `fix_when_guard_in_with_clause` — **the repair is a MOVE.** docs/18 groups
  `with ... <- ..., when` with the `def` shape, "delete the comma". That does not
  compile. Deleting the `when` does compile and is worse: a bare `with` clause is
  evaluated for its value and the value discarded, so the guard silently stops
  filtering — `with {:ok, x} <- {:ok, -5}, x > 0` returns `{:passed, -5}`. `with` does
  take a guard, before the `<-` (as Elixir's own `partition_supervisor.ex:446` and
  `uri.ex:493` write it), so the repair is `with {:ok, x} when x > 0 <- f()`. That is a
  move across the `<-`, which is why `FixMisplacedWhenGuard` — which only deletes —
  declines it rather than guessing. `WhenGuardPosition` already classifies the shape
  and returns `:none` for it, so this item is a new repair on an existing locator.
* ~~`fix_mixed_required_optional_map_keys`~~ **BUILT 2026-08-17**, as the disposition
  specified: a sibling of the live `Credence.Syntax.FixKeywordBeforePositionalArgument`,
  gated on the parse error carrying "unexpected expression after keyword list", located
  by the parser's own `{line, column}`, and REORDERING the keyword entry rather than
  deleting it.

  Two departures from the disposition, both measured.

  **It arrow-ifies rather than moving the entry last.** The disposition offered either.
  They are the same map — `%{a: 1, "k" => 2}` repaired either way evaluates to
  `%{:a => 1, "k" => 2}`, and as a `@type` the two differ only in key order, which a
  map type does not carry meaning for. Arrow-ify is the better edit: local, so comments
  and line structure survive; order-preserving; and it never needs to know where the
  container *ends*, which move-last does. Note that Elixir's own error message
  recommends reordering — that recommendation is for a human editing one map, not for a
  rewriter that must not disturb the rest of the file.

  **The decline list is `SourceMask`, not a character blacklist.** The disposition said
  to "decline outright when the container text contains any of `"` `'` `#` `~` `?` `\`
  `->`". That is the blunt instrument the sibling rule uses, and it would have declined
  the FIELD SAMPLE, whose container holds `"k" => 2`-style string keys and `optional(…)`
  calls. Masking the source instead means a decoy in a string or comment is invisible
  while a real defect beside a string key is still repaired.

  Scope is narrower than the name suggests, and every boundary was executed. The
  container must be `{` with `%` immediately before it — which is also what excludes
  structs, since `%Foo{` has `o` there. A list and a tuple raise the byte-identical
  error and arrow-ifying them is *invalid* (`[:a => 1, 2]` is `syntax error before:
  '=>'`), so they decline; their repair is move-last, a different rule with a different
  argument. `f(a: 1, 2)` is the sibling's. `%Foo{a: 1, "k" => 2}` would parse after the
  rewrite but the module would stay broken, because a struct cannot take a `=>` key at
  all — a different defect, so it declines rather than claiming a repair.

  The parser reports the comma immediately AFTER the offending keyword entry, so one
  entry per pass converges without the rule having to find the run boundary: on
  `%{a: 1, b: 2, "k" => 3}`, column 17 then column 11 then parses. All of it inside one
  `fix/1` call, which the single-pass round requires. Self-corruption measured
  structurally: 0 of 330 `lib/**/*.ex` files altered, since a rule keyed on a parse
  error cannot touch a file that parses.
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
