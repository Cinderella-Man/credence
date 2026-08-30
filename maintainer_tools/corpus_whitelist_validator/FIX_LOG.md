# Corpus-whitelist-validator — fix log

Working through the 71 `reports/batch_*.md` audits. 170 FLAGGED concerns collapse
into ~40 distinct rule defects + 2 systemic engine bugs. This log maps each
**root cause → fix → findings resolved**, so a root cause is investigated once even
though it recurs across many batches.

Severity legend: 🔴 ships wrong/uncompilable code · 🟠 over-fire false positive
(fix is a safe no-op today) · 🟡 no-op/self-revert (check/fix parity) · ⚪ cosmetic.

## Status

**31 rule defects + 2 systemic engine fixes landed**, resolving ~150 of the 170
flagged concerns. Every Tier-1 (ships-wrong-code) and Tier-2 (over-fire) defect is
fixed, plus the big Tier-3 no-ops (no_zip_then_map ×22) and the two
real-defect Tier-3 rules (no_duplicate_spec, no_list_append_in_reduce over-reach).
Each fix has check+fix regression tests (project style: full-string `== expected`).

- **Non-corpus suite:** 5291 tests, 0 failures (also resolved 2 pre-existing
  meta-test style violations).
- **Corpus fix-safety (500 pkgs / ~20k files):** 0 failures — no fix loses a
  comment, mangles a var, or over-reaches.

> ✅ **RESOLVED 2026-07-27 (Phase 4.5).** Closed by proof rather than by
> re-running: `test/corpus/over_firing_test.exs` asserts `actual == expected`
> **exactly**, so any pinned-but-no-longer-firing entry fails it with a `GONE`
> report naming the line. The full corpus scan is green (9,615 tests, 0
> failures, 20,076 files), therefore the snapshot contains no stale entries and
> there is nothing left to drop. Original note kept below for context.
>
> ⚠️ ~~**Action needed: regenerate `accepted_findings.txt`.**~~ The check narrowings
> (Tier-2 over-fires + several Tier-1 rules) intentionally make those checks stop
> firing on the whitelisted false positives. So the over-firing snapshot
> (`test/corpus/over_firing_test.exs`) now has stale entries that no longer fire —
> that is the *goal* (the whitelist shrinks as over-fires are fixed). Re-run
> `prepare_batches.sh` / regenerate the snapshot to drop them.

Remaining: one design decision (no_map_keys_or_values_for_iteration) and a tail of
harmless no-op/self-revert findings (safe via the apply_rule_fix gates). See the
bottom section.

---

## Systemic engine fixes (highest leverage — each kills a whole family)

### S1 · Comment DUPLICATION on re-rendered replacements — `apply_rule_fix` gate
- **Symptom:** a fix that carries a node's leading/trailing comment into its
  re-rendered replacement, while the original comment line (outside the patch
  range) survives, emits the comment **twice**. Compiles, behaviour-identical,
  but mangles source. `drops_comment?` only caught comment *loss*, not increase.
- **Findings (~19):** no_redundant_assignment (7), no_case_true_false (3),
  prefer_map_new_with_transform (1), no_find_value_default_case (1),
  no_redundant_enum_join_separator (1), use_map_join (1),
  no_underscore_function_name/scrivener (1), plus the dup half of others.
- **Fix:** generalise the comment gate in `RuleHelpers.apply_rule_fix/3` from
  "no comment dropped" to "comment multiset unchanged" (reject increase too).
  Duplicating fixes now self-revert (safe no-op) — same philosophy as the
  existing loss gate. STATUS: pending.

### S2 · Trailing-whitespace strip reaching unchanged heredoc/docstring lines
- **Symptom:** `strip_trailing_ws_per_line` ran over the *whole* fixed file,
  collapsing pre-existing whitespace-only lines anywhere — including inside
  `@doc`/heredoc string literals far from the patch — to empty, a content change.
- **Findings:** prefer_then_over_capture_invocation (batch_000),
  no_doc_false_on_private (batch_035), no_cond_two_clauses (batch_058),
  + general faithfulness across all rules.
- **Fix:** only normalise whitespace-only lines that the patch actually
  introduced (myers-diff vs original; collapse only `:ins` lines, keep `:eq`
  lines byte-for-byte). STATUS: pending.

---

## Per-rule defects (triaged)

### 🔴 Tier 1 — fix ships wrong or uncompilable code
| Rule | Findings | Root cause | Planned fix |
|---|---|---|---|
| no_destructure_reconstruct | 8 | reassignment-blind: pattern vars rebound between destructure and reconstruction; collapsing to `= items` returns stale input | bail if any destructured var is reassigned before the reconstruction site |
| no_underscore_function_name | 6 | (a) renames `:erlang.load_nif` NIF stubs → breaks native binding; (b) call-site updater misses bare-pipe no-arg `{name,_,atom}` refs → undefined-fn compile error | skip modules that call `load_nif`; revert/skip when a no-arg context-atom ref to the renamed name exists |
| no_list_append_in_recursion | 5 | flips only one append site / reverses one base case while sibling terminals still append, or acc read mid-loop → reordered output | only fire when ALL append sites flippable + ALL bases reversed + acc not read elsewhere in body |
| prefer_guard_over_if | 6 | (a) duplicates `\\ default` onto both split heads → compile error; (b) renames `assigns`→`_assigns` breaking `~H`; (c) reuses existing `_`-name → equality constraint; (d) underscores a non-linear join var | exclude default-arg heads; don't rename ~H assigns / join vars; fresh collision-free underscore |
| prefer_function_capture | 5 | rewriting an `fn` that sits inside an enclosing `&` capture → "nested captures not allowed" | bail when the fn is lexically inside an enclosing capture |
| no_kernel_op_in_pipeline | 4 | `Kernel.op` step is LHS of a further `|>`; unwrapping to infix flips precedence / strands downstream pipe | bail (or parenthesise) when the op step is consumed by a downstream pipe; skip upstream-less quoted fragments |
| no_piped_regex_replace | 4 | piped LHS is a Regex (`~r//`, `Regex.compile!`), rewrite to `String.replace` puts a %Regex{} in the subject slot → crash | only fire when piped subject is provably a string, not a regex |
| no_redundant_comparison_guard | 3 | "complementary earlier clause" matched on `{name,arity}` only, ignoring head pattern → drops a needed guard | require same head argument pattern before deeming a guard redundant |
| prefer_erlang_float | 3 | fires inside `defn`/`defnp` (tensor ops) and `use Image.Math` operator-overload scope → `:erlang.float` on a struct/tensor | skip in defn bodies and operator-overloaded scopes |
| no_duplicate_function_clauses | 4 | normalizer collapses `%__MODULE__{}`≡`%_{}`, pipe-form guards, and ignores `@attr` redefinition / different bodies → deletes a non-duplicate | keep struct-name + guard identity; require same body; resolve @attr per clause |
| no_redundant_underscore_bind | 11 | fires on statement-position `_ = var` (the warning-suppression idiom), not just pattern position; rewrite reintroduces the warning | restrict to genuine pattern position (heads/clause patterns), never `__block__` statement position |
| no_case_on_param_dispatch | 2 | scrutinee var binding lost when body still references it; dup head generated | bind scrutinee (`= var`) when body needs it; skip if dup head exists |
| no_sort_then_at | 1 | comparator-only `Enum.sort(fn)` misread as collection | bail when sort's only arg is a comparator fn |
| no_unless_else | 1 | rewrites a DSL `def unless` (non-Kernel) | exclude `unless` as a def head / non-Kernel form |
| no_eager_with_index_in_reduce | 1 | drops the offset arg of `Enum.with_index(list, n)` | preserve the offset (or skip when non-default) |
| no_length_comparison_for_empty | 1 | quoted-then-spliced into a guard; `!= []` differs from `length>0` on non-lists | don't rewrite length comparisons quoted into a guard |
| no_empty_map_new | 1 | `&Map.new/0` capture rewritten to `&%{}/0` → invalid | skip Map.new as operand of `&.../0` |
| no_manual_frequencies | 1 | non-var (map) reduce element param → emits `fn nil ->` unbound | require a genuine plain-variable element param |
| no_redundant_to_list | 1 | strips `Enum.to_list` feeding `Map.take` a MapSet → deprecation/breakage | don't strip when consumer needs a list (MapSet→Map.take) |
| non_grouped_clauses | 2 | single-statement do-block body re-rendered as `do:` swallows a `with`/`case` block; directive between clauses suppresses the warning | guard body containing a do-block; don't flag when a directive separates clauses |

### 🟠 Tier 2 — over-fire false positives (fix is a safe no-op today; narrow the check)
| Rule | Findings | Root cause | Planned fix |
|---|---|---|---|
| no_map_update_then_fetch | 13 | module-wide var-name match, no scope/adjacency/key check | require same-block adjacency + matching key (mirror the fixer) |
| no_missing_require_logger | 7 | blind to aliased Logger, enclosing-module require, `use`/`__using__` injection | resolve alias; consider enclosing scope; treat `use` as a possible provider |
| no_nested_enum_on_same_enumerable | 9 | name-only enumerable match, blind to reduce accumulator / clause-pattern shadowing; check broader than member?-only fixer | bind/scope-aware matching + restrict check to fixer's cases |
| no_keyword_get_integer_key | 3 | misreads `Keyword.get(:key, default_int)` (pipe desugaring) — default int taken as key | account for pipe; require integer in key position |
| hallucinated_guard | 1 | `defined_guards/1` blind to `import`ed custom guards; fires in expression position | recognise imported guards; don't fire in expression position |
| prefer_no_question_mark_for_non_boolean | 1 | `boolean_type?/1` misses the `bool()` alias | recognise `bool()` |
| no_map_then_aggregate | 1 | emits one finding per enclosing pipe step instead of per fusion site | dedupe by fusion site |

### 🟡 Tier 3 — no-op / self-revert (check/fix parity)
| Rule | Findings | Root cause | Planned fix |
|---|---|---|---|
| no_zip_then_map | 22 | `transform_node/1` applied to root only (no tree walk) → 0 patches everywhere | wrap transform in a walk (postwalk) so nested zip→map sites rewrite |
| no_map_keys_or_values_for_iteration | 3 | whole-file transform rewrites order-dependent excluded callbacks; callback-less terminals no-op | gate fix by @fixable_funcs; exclude callback-less terminals |
| prefer_cond_for_nested_if | 3 | inner comment dropped → comment gate self-reverts | preserve inner comment or treat check-only |
| no_cond_two_clauses | 3 | get_range render of multi-line piped cond; inner-cond reflow; heredoc strip (→S2) | surgical patch; S2 |
| no_case_boolean_result | 2 | leading comments dropped → gate self-revert (all-or-nothing per file) | per-patch gating or preserve comments |
| no_guard_equality_for_pattern_match | 2 | rewrite round-trips to identical source | don't surface as fixable when guaranteed no-op |
| no_duplicate_spec | 2 | dedup key blind to annotated `{name,arity}` | key dedup on annotated function |
| (singletons) | — | various no-op/self-revert | per-case: make fix work or mark check-only |

---

## Applied fixes (chronological)

### ✅ S1 — comment-multiset gate in `apply_rule_fix` (`lib/rule_helpers.ex`)
Generalised the comment-loss gate to reject any change to the comment multiset
(loss OR duplication). `drops_comment?` → `comments_changed?` / `comment_multiset/1`.
- **Verified self-revert (was comment-dup):** no_redundant_assignment
  (propcheck statem_dsl.ex:547), no_case_true_false (regex.ex:1056),
  prefer_map_new_with_transform (transaction_handler.ex:226),
  use_map_join (device_codes.ex:228). Resolves the comment-dup half of
  no_find_value_default_case, no_redundant_enum_join_separator,
  no_underscore_function_name/scrivener, and the `no_redundant_assignment` family (7).
- Full non-corpus suite: no new failures (2 failures are **pre-existing**
  test-style violations in hallucinated_guard / no_list_append_in_reduce /
  prefer_map_new_with_transform fix tests — to clean when those rules are fixed).

### ✅ S2 — surgical trailing-whitespace strip (`lib/rule_helpers.ex`)
`strip_trailing_ws_per_line(text)` → `(text, original)`: myers-diff vs the
original and collapse whitespace-only lines only in `:ins` (patch-introduced)
hunks, leaving every `:eq` line byte-for-byte. Stops the whole-file strip from
mutating unchanged heredoc/docstring content far from the edit.
- **Verified surgical (was far-away @doc strip):** no_doc_false_on_private
  (hound element.ex:331 — only `@doc false` removed), no_cond_two_clauses
  (statistics beta.ex:23 — only the cond→if hunk, no lines 38/54 strip),
  prefer_then_over_capture_invocation (absinthe_federation notation.ex:630 —
  only the two pipe hunks, no line-262 strip).
- No new test failures.

### ✅ no_destructure_reconstruct — bail on reassigned vars (8 findings, 🔴)
Added `reassigns_any?/2`: bail (in both `check` and `fix`) when any destructured
variable appears on the LHS of a `=` or `<-` in the body — the `= items` collapse
would otherwise return the original, stale values instead of the recomputed ones.
- **Verified:** explorer data_frame.ex:924, murmur hash_128_x64.ex:49, image
  yuv.ex:356 → now `[NO CHANGE]`. ex_cldr config.ex:613 → the reassigning `true`
  clause is now skipped; only the adjacent clean `false` clause is fixed (correct
  — narrowed to the safe core, sibling-clause-precise).
- Tests: +4 (check: `=` rebind, `<-` rebind, sibling-clause precision; fix:
  reassigned-var unchanged). 32 tests pass.

### ✅ no_empty_map_new — skip `&Map.new/0` arity capture (1 finding, 🔴)
Added a clause in both walkers to not descend into `{:&, _, [{:/, _, [_fun, _arity]}]}`.
The `Map.new` in `&Map.new/0` is AST-identical to a real `Map.new()` call;
rewriting it produced `&%{}/0` ("invalid args for &"). **Verified:** blacksmith
sequence.ex:41 → `[NO CHANGE]`. Tests: +1. 12 check tests pass.

### ✅ no_sort_then_at — piped-collection direction (1 finding + latent bug, 🔴)
The piped form `xs |> Enum.sort(arg) |> Enum.at(i)` misread the lone `arg` as the
collection: a custom comparator fn → wrong; `:desc`/capture → silently wrong
direction; fix kept a stray `|> Enum.sort()`. Added `pipe_sort_direction/2` (when
collection is piped, prepend a placeholder so the lone arg is read as a direction),
and fixed clause 2 to operate on `deeper` directly. **Verified:** eventstore
migrate.ex:127 (complex comparator) → `[NO CHANGE]`; `xs |> Enum.sort(:desc) |>
Enum.at(0)` → `Enum.max(xs, fn -> nil end)` (was wrongly `Enum.min(xs |>
Enum.sort(),…)`). Tests: +4. 72 tests pass.

### ✅ no_eager_with_index_in_reduce — preserve the offset arg (1 finding, 🔴)
`Enum.with_index(list, n)` → `Stream.with_index(list)` dropped the offset `n`,
shifting every index. Now pass `wi_args` through to `Stream.with_index/2`
(direct form); the `:reduce` strategy (whose accumulator index starts at 0)
falls back to `:stream` when an offset is present, via `with_index_has_offset?/1`
(offset is the 1st arg when with_index is piped, 2nd when direct). **Verified:**
plausible form.ex:453 → `Stream.with_index(funnel.steps, 1)`. Tests: +3. 20 fix
tests pass.

### ✅ no_unless_else — skip modules that define their own `unless` (1 finding, 🔴)
`Explorer.Query` defines `def unless/2,3` (a query DSL); the `def unless(c, do:,
else:)` head is shaped exactly like a `Kernel.unless ... else` call, so the rule
rewrote both the head and in-module calls to `if`, breaking the DSL. Added
`defines_unless?/1` (detects a local `def*` named `unless`); when present, `check`
and `fix` return `[]`. **Verified:** explorer query.ex:709 → `[NO CHANGE]`. Tests: +2.

### ✅ no_manual_frequencies — require a plain-variable element param (1 finding, 🔴)
`fn %{block_number: number}, acc -> …` has a map-pattern element; `var_name/1`
returns `nil`, but `is_atom(nil)` is true so the guard let it through, emitting
`fn nil -> …` with the body var unbound. Guarded the `with` against `nil`.
**Verified:** blockscout fetcher.ex:312 → `[NO CHANGE]`. Tests: +1.

### ✅ prefer_function_capture — skip fns nested in an enclosing `&` (5 findings, 🔴)
Rewriting `fn x -> f(x) end` inside `&Enum.map(&1, …)` produces an illegal nested
capture. Added `captured_fn_positions/1` (positions of every fn inside a `&`,
keyed by unique `{line, column}`); check and fix skip those. **Verified:**
firezone sites.ex:827, hexpm audit_log.ex:367, moar map.ex:119 → `[NO CHANGE]`;
top-level fns still rewritten. Tests: +3.

### ✅ no_piped_regex_replace — only fire on genuine misuse (4 findings, 🔴)
`regex |> Regex.replace(string, repl)` is the CORRECT form; the rule rewrote it
to `String.replace`, putting a %Regex{} in the subject slot (crash). Added
`misused_pipe?/1`: fire only when the explicit first arg (string slot) is itself
a regex (`~r`/`~R`, `Regex.compile`/`compile!`) — the tell that the pipe injected
a string into the regex slot. **Verified:** ex_phone_number formatting.ex:110,
ja_serializer link.ex:48, surface surface.format.ex:98 → `[NO CHANGE]`; true
misuse still fixed. Tests: +4.

### ✅ no_kernel_op_in_pipeline — don't flatten ops consumed by a surviving pipe (4 findings, 🔴)
Flattening `Kernel.op` to infix when the op-pipe is the LHS of a surviving `|>`
(`|> case`, `|> f.()`) flips precedence (`|>` binds tighter than the ops). Added
`collect_unsafe/3` which propagates a "consumed by a surviving pipe" context down
each pipe chain — a full chain of flagged ops flattens together (safe), but any
non-flagged step above an op taints it. Also skip quoted fragments (zero-arity
call LHS + `unquote`) destined to be spliced into a pipe. **Verified:** assent
telegram.ex:178, doctor report_utils.ex:182, mockery assertions.ex:449 →
`[NO CHANGE]`; chained `Kernel.== |> Kernel.or` still flattens. Tests: +2 (2 prior
test expectations confirmed correct under propagation).

### ✅ no_redundant_comparison_guard — require identical head patterns (3 findings, 🔴)
The "complementary earlier clause" was matched by `{name, arity}` only, ignoring
head argument patterns — so a `:non_neg_integer`-tagged clause was deemed
redundant against a `:neg_integer`-tagged one (dropping `value >= 0` lets
negatives return `:ok`). Threaded the head args through check & fix, added
`same_head?/2` (structural equality modulo metadata). **Verified:** ham
type_engine.ex:146, hammox type_engine.ex:165 → `[NO CHANGE]`; pathex
force_updater.ex now strips only the genuinely-redundant same-head `{:tuple,n}`
`< 0` (the unsafe cross-head pairing is blocked). Tests: +2.

### ✅ prefer_erlang_float — skip defn bodies & operator-overloaded modules (3 findings, 🔴)
`* 1.0` is float coercion only when `*` is the Kernel operator on a number. Added
`overrides_arith_operators?/1` (module-level: `use *.Math`, `import Kernel,
except: [*: 2]`) → skip whole file, and `defn_operator_positions/1` (per-node:
operators inside `defn`/`defnp` are tensor math). **Verified:** image image.ex:10563,
nx lin_alg.ex:2032, scholar trimap.ex:451 → `[NO CHANGE]`; normal `def n * 1.0`
still → `:erlang.float(n)`. Tests: +5.

### ✅ no_underscore_function_name — NIF gate + bare-pipe exclusion (6 findings, 🔴)
(a) Renaming `:erlang.load_nif` NIF stubs orphans the native binding → added
`loads_nif?/1` (match `.load_nif` regardless of how `:erlang` is wrapped); when
true, check & fix bail for the whole file. (b) Bare-pipe refs `x |> _value` have
AST `{:_value, _, ctx}` (no arg list) the call-site updater can't rewrite →
added `bare_reference_names/1`, unioned with `captured_arity_names` into
`excluded_names/1`. **Verified:** appsignal nif.ex:217, sweet_xml sweet_xml.ex:763,
tzdata util.ex:36 → `[NO CHANGE]`; normal `_g`→`do_g` still renamed. Tests: +2.
(The remaining public-`def` rename concern is intentionally kept — there is an
explicit test asserting `def _helper` is flagged; rated LOW by the auditor.)

### ✅ no_redundant_underscore_bind — pattern position only (11 findings, 🔴)
Fired on `_ = var` in STATEMENT position (the warning-suppression idiom in
NimbleParsec/macro-generated code); rewriting to bare `var` reintroduces the
"variable has no effect" warning. Added `pattern_bind_positions/1` — only `_ =
var` in `def` head args, `->` clause heads, and `<-` generators is flagged.
**Verified:** date_time_parser combinators.ex, ex_cldr rfc5646_parser.ex,
ex_cldr_dates_times date.ex, domo lists.ex (quote-block) → `[NO CHANGE]`;
`def foo(_ = x)`/`case … _ = x ->` still fixed. Tests: 3 old tests that encoded
the bug (rewriting statement-position `_ = x`) updated to assert the corrected
scope; +2 new. 25 tests pass.

### ✅ prefer_guard_over_if — 4 unsafe sub-cases (6 findings, 🔴)
Shared `splittable?/3` between check & fix; added two bail guards and hardened the
param-underscoring:
- `head_has_default?/1` — a `\\` default can't be declared on both split heads
  (compile error). Bail. (list pop_at, glific, hexpm → `[NO CHANGE]`)
- `body_has_h_sigil?/1` — `~H` needs a literal `assigns`; underscoring it breaks
  compile. Bail. (plausible notice.ex → `[NO CHANGE]`)
- `safe_to_underscore?/4` — never underscore a non-linear (repeated, count≠1) head
  var (join constraint) or one whose `_name` already exists (collision). (logflare
  syn_event_handler.ex, sobelow parse.ex → now SAFE: `_timestamp1`/`type` preserved,
  fixed output parses & preserves behaviour.)
Tests: +4 (default & ~H not flagged; non-linear & collision safe fixes). 50 tests pass.

### ✅ no_duplicate_function_clauses — 4 normalizer bugs (4 findings, 🔴)
Unified check & fix into one `duplicate_clauses/1`; the signature now includes the
normalized BODY and referenced `@attr` versions, and the normalizer keeps two
previously-collapsed forms distinct:
- `%__MODULE__{}` vs `%_{}` — `__MODULE__` kept literal (matches only this module's
  struct) vs `_` placeholder (any struct). (ash typed_struct.ex)
- pipe-form guards `x |> is_list` — RHS bare name normalized as a `{:fn_ref, …}`,
  not a placeholder, so `|> is_list` ≠ `|> is_binary`. (socket address.ex)
- `@attr` redefined between clauses — `attr_assignment_name/1` bumps a per-attr
  version threaded through the block; a clause's signature carries the versions of
  the attrs it references, so two `when op in @ops` clauses with `@ops` reassigned
  between them stay distinct. (logflare helpers.ex)
- same head, different body — body in the signature means a copy-paste clause with
  a different body is no longer silently deleted (surfaced as a likely author bug).
  (logflare protobuf_formatter.ex)
**Verified:** all 4 corpus sites → `[NO CHANGE]`. Tests: 1 old test (asserted
different-body deletion) made a true duplicate; +4 new. 27 tests pass.

### ✅ no_redundant_to_list — only `.new` accepts arbitrary enumerables (1 finding, 🔴)
Fired on any `Map.*`/`MapSet.*` func; a piped `record |> Map.take(Enum.to_list(…))`
made `Enum.to_list(…)` the first explicit arg, so stripping it passed a non-list
enumerable (MapSet) to `Map.take`'s keys slot (deprecated). Restricted the guard
to `func == :new`. **Verified:** ash generator.ex:441,:502 → `[NO CHANGE]`. Tests: +1.

### ✅ no_case_on_param_dispatch — bind scrutinee past bitstring type specs (1 HIGH of 2, 🔴)
`binds_var?` mistook the `::binary` type specifier in `<<number::utf8, _::binary>>`
for a binding of a scrutinee named `binary`, so the head didn't bind it and the
body's `binary` reference was undefined (compile error). Added
`strip_bitstring_types/1` (replace the type side of `::` before the binding
check) → the head now emits `<<…>> = binary`. **Verified:** json number.ex:45 →
`def parse(<<number::utf8, _::binary>> = binary)`, parses. Tests: +1. (The LOW
cosmetic dead-duplicate-head from batch_005 left as-is — compiles, behaviour-safe.)

### ✅ non_grouped_clauses — 2 bugs (2 findings)
- 🔴 batch_028: a clause whose single-statement body is a `do…end` block
  (`with`/`case`/…) mis-renders to `def/3` when moved (only multi-statement bodies
  were skipped). `multi_statement_body?` → `unsafe_to_move_body?` (also skips
  single-statement do-block bodies via `do_block_statement?/1`). (ex_cldr_calendars
  calendar.ex now parses; safe clauses still regroup.)
- 🟠 batch_044: a `require`/`import`/`alias` directive between clauses doesn't
  trigger Elixir's warning — made those group-preserving in
  `previous_key_after_non_function/2`. (lexical intelligence.ex no longer flagged.)
Tests: +2. 24 tests pass.

### ✅ no_length_comparison_for_empty — skip quoted comparisons (1 finding, 🔴)
A `length(x) > 0` inside a `quote` may be spliced into a guard, where `x != []`
matches a non-list (the guard `length` would raise → skip) — a dispatch change.
Added `collect_quoted_member_ids/1`, unioned with guard ids into `skip_ids/1`.
**Verified:** domo lists.ex:136 → `[NO CHANGE]`; plain `length(list) > 0` still →
`list != []`. Tests: +1. 31 tests pass.

---

## Tier-2 over-fires (narrow the check)

### ✅ no_map_update_then_fetch — same-block adjacency + key (13 findings, 🟠)
Two file-global passes (collect every var bound by `Map.update`, flag every
`Map.fetch!/get` on that name anywhere) ignored scope, adjacency, and key. Replaced
the check with `detect_in_block/1`, which reuses the fix's own pairing
(`extract_map_update` → `find_matching_fetch`): a `var = Map.update(map, key, …)`
whose updated var is *next referenced* in the same block by `Map.fetch!/get(var,
key)` with a matching key. **Verified:** absinthe mark_referenced.ex:144, grpc
gun.ex:37, spitfire.ex:320, mobilizon event.ex:169 no longer flagged; genuine
adjacent same-key pair still flagged + fixed. Tests: +3. 9 check tests pass.

### ✅ prefer_no_question_mark_for_non_boolean — recognise `bool()` (1 finding, 🟠)
`boolean_type?/1` missed the deprecated `bool()` alias, so `:: bool()` predicates
got their `?` stripped. Added a `{:bool, _, _}` clause. **Verified:** appsignal
integration_logger.ex:62 → `[NO CHANGE]`. Tests: +1.

### ✅ no_keyword_get_integer_key — pipe desugaring (3 findings, 🟠)
A piped `opts |> Keyword.get(:timeout, 5000)` is `Keyword.get/3` (atom key,
integer DEFAULT) but the direct 2-arg clause read the default as the key. Added
`piped_get_positions/1`; the direct 2-arg clause now fires only when NOT piped
(the rule already excludes 3-arg calls). **Verified:** archethic
validate_smart_contract_call.ex:88, firezone offset_paginator.ex:42 not flagged;
genuine `Keyword.get(opts, -1)` / `opts |> Keyword.get(0)` still flagged. Tests: +2.

### ✅ hallucinated_guard — defer on import/use (1 finding × 22 lines, 🟠)
`is_pos_integer` etc. can be REAL custom guards brought in via `import MyApp.Guards`;
the rule was blind to imports and unrolled them (possibly to a divergent
definition). Since an unqualified guard that compiles must be locally defined or
imported, added `imports_or_uses?/1` — when present, check fires on nothing and
fix returns []. **Verified:** logflare s3_adaptor.ex (imports guards) → not flagged;
hallucinated guard in an import-free module still flagged. Also cleaned the fix
test's `Code.string_to_quoted`/`=~` style violations (resolves the FixMeta
meta-test failure). Tests: +6.

### ✅ no_missing_require_logger — scope-aware satisfaction (7 findings, 🟠)
Rewrote check & fix to share `unsatisfied_modules/1`, a scope-aware walk: a module
is satisfied (not flagged, no insert) when `require Logger` is in scope from the
module OR any enclosing module / file scope (lexical propagation), OR an `alias`
makes `Logger` a non-stdlib module, OR a custom (non-stdlib) `use` is present
(its `__using__` may inject the require — `@stdlib_use_targets` excludes
GenServer/Agent/… so those still flag). Also restored whole-body require detection
(require co-located in a function). **Verified:** conform, logflare postgres_strategy,
realtime cdc_rls, kino screen, membrane sip/call, sequin trace, firezone client →
all 0. Tests: 1 old test (asserted nested doesn't inherit) corrected; +5. 36 tests pass.

### ✅ no_nested_enum_on_same_enumerable — restrict to nested member? (9 findings, 🟠)
The fixer only rewrites a nested `Enum.member?` (→ MapSet), but the check fired on
every nested Enum call (map/filter/reduce) — no-op findings, plus false positives
where the "same" name was a rebound reduce accumulator. The check now flags only a
nested `member?` enclosed by a non-member? traversal of the same var. **Verified:**
ash calculations.ex, geo decoder.ex:299, keila hasher.ex:112 no longer flagged;
genuine `member?`-in-`map` still flagged. Tests: +2. 7 check tests pass.

### ✅ no_map_then_aggregate — dedupe by fusion site (1 finding, 🟠)
`check_pipeline` scanned every adjacent pair of the flattened pipeline, so
`map |> sum |> Kernel.+ |> Float.round` reported the map→sum fusion once per
downstream `|>` (pointing at unrelated steps). Now `check_node` checks only the
immediate pair at each `|>` (`agg_step?(right) and map_step?(rightmost(left))`),
firing once at the real fusion. **Verified:** long chain → 1 finding; changelog
episode.ex/podcast.ex now report at the real fusion lines. Tests: +1. 16 tests pass.

---

## Tier-3 no-op / self-revert (make the fix work or mark check-only)

### ✅ no_zip_then_map — make the fix walk the tree (22 findings, 🟡)
`fix_patches` passed `&transform_node/1` straight to `patches_from_ast_transform`,
which only applies it to the module root — so the fix was a silent no-op for every
real (nested) occurrence. Wrapped it in `Macro.postwalk`. `Enum.zip(a,b) |>
Enum.map(fn {x,y} -> e end)` → `Enum.zip_with(a, b, fn x, y -> e end)` is
byte-equivalent. **Verified:** all 43 corpus files with this finding now produce a
changed, parsing, comment-preserving fix (none raise/self-revert); diffs are
surgical (3–6 lines); trailing pipes preserved. Corpus fix-safety test re-run to
confirm no over-reach. 28 unit tests pass.

> **Full corpus fix-safety test: 500 packages / 500 tests / 0 failures** — run
> after enabling no_zip_then_map and all rule changes; confirms NO comment loss,
> mangling, or over-reach across ~20k corpus files for every rule.

### ✅ no_duplicate_spec — key dedup on the annotated function (2 findings, 🟡/🔴)
Dedup keyed on spec *text* only, deleting textually-identical specs that annotate
DIFFERENT functions (the correctly-placed `start_link/0` spec deleted as a "dup"
of a misplaced one; `@spec test_project` above `def phx_test_project` deleted).
Now keyed on `{spec_text, following_def_name_arity}` via shared
`duplicate_spec_indices/1`. **Verified:** igniter test.ex:58 → `[NO CHANGE]`;
exredis now keeps the correctly-placed `/0` spec (removes only a true redundant
copy); genuine same-function duplicate still removed. Tests: +2. 9 tests pass.

### ✅ no_list_append_in_reduce — surgical piped patch (1 finding, 🔴 over-reach)
The piped fix wrapped `lhs |> reduce` into `(lhs |> reduce) |> reverse`; the
AST-diff then mis-aligned and corrupted an unrelated upstream node — an Ecto
`[mb, flow]` join binding 27 lines away became `[[mb, flow]]` (parses, so the
corpus over-reach detector — which only catches whitespace reflows — missed it).
Split the fix: the standalone reduce keeps the diff path; the PIPED form now emits
a surgical byte-range patch on ONLY the reduce step (` |> Enum.reverse()` appended
textually), leaving `lhs` byte-for-byte. **Verified:** glific reports.ex:400 join
binding now intact; standalone/simple/unsafe forms all correct. Also cleaned the
fix test's `Code.string_to_quoted` style violation. Tests: +1 regression. 18 tests.

---

### ✅ no_map_keys_or_values_for_iteration — fix scope = check scope (3 findings, 🟠→🔴 order-divergence)
The check's `@fixable_funcs` is the order-INDEPENDENT subset (all?/any?/count/
empty?/frequencies/frequencies_by), but the fix (`fix_nested`/`fix_pipe`) also
rewrote order-DEPENDENT ops (filter/find/at/take/reduce/map/join/…). Applied to a
file, it rewrote unflagged `Map.values() |> Enum.filter(...)`, whose result order
diverges for >32-key maps. Gated BOTH the check and the fix on one shared
`fixable?/2` predicate (`enum_fn in @fixable_funcs and safe_callbacks?`), removed
the order-dependent fix branches + 8 now-dead helpers, and rewrote the fix tests
(the ~70 order-dependent rewrite tests asserted removed behaviour → replaced with
no-op coverage + kept the fixable-op tests). **Verified:** membrane
endpoint_manager.ex — the filter at 75/119 is no longer rewritten (only the safe
`Enum.count` is). 63 rule tests pass; clean compile.

## Check/fix scope-parity audit (beyond the 71 reports)

After fixing no_map_keys, I audited ALL rules for the same bug class — a fix that
fires where its check is clean. (Neither the over-firing test nor the fix-safety
test catches this direction: the check is clean so the over-firing snapshot never
sees it, and the fix is safe so fix-safety passes.) The audit: for each rule ×
every hex-corpus file (146 × 10,172), flag any file where `rule.check(ast,[]) ==
[]` yet `apply_rule_fix` nets a change. It found exactly **2** real mismatches —
both now fixed:

### ✅ NoMapKeysEnumLookup — fix missing the check's 3rd condition (🔴)
The check requires the callback to look up the map (`m[k]`/`Map.get(m,k)`), but the
`apply_*_fix` paths didn't — so `Map.keys(m) |> Enum.any?(fn k -> k in @kw end)`
(key-only callback) got rewritten to `Enum.any?(m, fn {k, v} -> … end)`, an unused
`v` binding on code the check leaves clean. Gated all three `apply_*` paths on
`references_map_var?/2` (the check's condition). **Verified:** xema json_schema.ex
→ `[NO CHANGE]`; genuine value-lookup case still fixed. Tests: +2.

### ✅ NoRedundantEnumJoinSeparator — fix collapsing clean pipes (🟠)
A "collapse single-step pipe" fix clause un-piped ANY `x |> Enum.join()` (no
separator) into `Enum.join(x)` — clean code the check never flags. Removed the two
collapse clauses; dropping the redundant `""` now leaves the (already-correct)
piped form `x |> Enum.join()`. **Verified:** waffle versioning.ex → `[NO CHANGE]`;
flagged `Enum.join(x, "")` / `x |> Enum.join("")` still fixed. Tests: 4 updated (the
collapse was asserted) + 2 regression.

> After both fixes the audit reports **0 scope violations** across all 146 rules —
> every rule's fix nets a change ONLY where its check fires.

### ✅ Permanent guard: `test/corpus/scope_parity_test.exs`
Turned the audit into a `:corpus` meta-test (sibling to fix_safety / over_firing).
Invariant: for every rule × every corpus file, `rule.check(ast, []) == []` ⟹
`apply_rule_fix(rule, src) == src` (a fix changes code only where its check flags).
Cheap `fix_patches/2` pre-filter, full-pipeline confirm only on candidates; a
failure prints the rule, file, and the offending diff hunk. **Verified:** passes
**500 tests / 0 failures** across all 20,076 corpus files (146 rules); and a
deliberately reintroduced over-reach was caught in 8s with a readable message,
then reverted. Closes the gap neither over_firing (check-only) nor fix_safety
(flagged-files-only) covered.

## Known issues deferred for a design decision

### Harmless no-op / self-revert findings (safe via the apply_rule_fix gates)
The remaining Tier-3 findings safely self-revert through the parse/comment gates —
they ship NO bad code (confirmed by the 500/0 corpus fix-safety run). They are
check/fix-parity cosmetics (a fixable-labelled finding that no-ops on a specific
site because a comment/precedence/get-range edge trips the gate):
prefer_cond_for_nested_if (inner comment dropped → comment gate), no_case_boolean_result
(leading comments → comment gate), no_cond_two_clauses (multi-line piped cond render;
heredoc strip now handled by **S2**), no_guard_equality_for_pattern_match (rewrite
round-trips identical), no_list_concat_with_recursive_result (charlist cons render),
no_redundant_list_traversal / no_if_true_false / no_manual_list_reduce-span / etc.
Each could be made check-only or comment-preserving per-rule, but none are
correctness risks.
