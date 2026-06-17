# 09 — Real-world corpus over-firing tests

## Context
Credence rules are deliberately narrowed to safe cores; the live risk is **over-firing**
— a rule flagging idiomatic real code. This layer runs Credence over the `lib/` source of
~10 pinned popular hex packages and asserts it leaves them untouched. Premise (verified
sound): that code is good → Credence should find nothing; any finding = a likely over-fire
to investigate. Must live in the default `mix test`, stay fast (the suite runs in a tight
loop while rules evolve), and fetch once.

## Status: ✅ DONE — corpus is a GREEN regression ratchet in the default `mix test`

> Reconciliation complete, then the rule-level allowlist was **replaced by a per-finding
> snapshot ratchet** (see "Snapshot ratchet" at bottom). Each accepted finding is pinned by
> identity — `<path>:<line>  <rule>` — in `test/corpus/accepted_findings.txt`; the test asserts
> the live set equals the pin per package, so a NEW finding (a candidate over-fire) fails the
> suite with a diff instead of being silently swallowed by a whole-rule allowlist. The
> `:corpus` exclude is removed from `test_helper.exs`, so it runs in plain `mix test`. Full
> suite: **5162 tests, 0 failures**. Historical triage/progress below is kept for the record.

## (historical) Status: harness BUILT + verified; corpus surfaces 1760 findings (triage below)

Built & verified:
- `test/support/corpus.ex` — `Credence.Corpus`: pinned `{pkg, version}` list, `dir/1`,
  `lib_files/1`, idempotent `ensure_fetched!/0` (shells `mix hex.package fetch` only when a
  pin is missing/mismatched).
- `test/corpus/over_firing_test.exs` — one `test` per package, `@moduletag :corpus`,
  `async: true`, asserts `Credence.Pattern.analyze == []` (skipping `:parse_error`); failure
  message lists `path:line  rule` sorted.
- `test/test_helper.exs` — `ExUnit.start(..., exclude: [:corpus])`.
- `.gitignore` — `/corpus/`.
- Verified: default `mix test <file>` → `10 excluded`; `mix test <file> --include corpus` →
  runs, fails with the per-package finding lists as designed.

## Decisions
- **Scope: Pattern phase only**, via `Credence.Pattern.analyze/2` (parse-only — no
  compilation, no module load). On clean packages Syntax fires only on unparseable source
  (`lib/syntax.ex:17`) and Semantic only on rule-matched warnings/errors that correct code
  doesn't emit (`undefined_function` matches `"undefined or private"` / `"deprecated"`,
  NOT the `"module not available"` form — so e.g. `tesla → Hackney` optional-dep refs do
  not trip it). So the full pipeline reduces to Pattern anyway — but full `Credence.fix`
  still pays ~3 `Code.compile_string`/file regardless of firing (~2-4 min) and its Pattern
  *fix* is compile-gated (`lib/pattern.ex:52`, skips macro-heavy files). Parse-only
  `analyze` is ~10× faster, fuller coverage (checks every file), and the same over-fire
  signal.
- **Assertion: strict-zero.** `Credence.Pattern.analyze(source) == []` per file (after
  dropping `:parse_error` issues). Any finding fails the test — matches the
  narrow-the-rule methodology: a new rule that over-fires goes red immediately.
- **Packages: max-coverage 10** (all Elixir w/ `lib/*.ex`): jason, plug, ecto, phoenix,
  decimal, gettext, poison, tesla, floki, credo. Exact versions resolved at implementation
  (`mix deps.get`) and pinned in the committed `mix.lock`.

## Implementation
### 1. Pin packages — `mix.exs` `deps/0`
Add the 9 not already declared (credo is already `{:credo, "~> 1.7", only: [:dev, :test]}`
— reuse its `deps/credo/lib`) as exact-pinned, test-only, non-runtime:
`{:jason, "x.y.z", only: :test, runtime: false}`, … Run `mix deps.get` once → source lands
in `deps/<pkg>/lib` (gitignored, reused across runs), versions locked in `mix.lock`.
*Tradeoff:* mix also compiles these + their transitive trees on first `mix test` (wasted
for parse-only, one-time, cached). The alternative in Q1 below avoids it.

### 2. Corpus test — `test/corpus/over_firing_test.exs`
- `use ExUnit.Case, async: true` (analyze is pure — safe to parallelize).
- `@packages [{:jason, "x.y.z"}, …]` hardcoded (atom + pinned version; documentary +
  drives the per-package tests).
- Generate **one `test` per package** (loop `@packages` at compile time) so failures
  localize to a package.
- Per package: resolve `lib` via `Mix.Project.deps_paths()[pkg]` joined with `"lib"`;
  `Path.wildcard("**/*.ex")`; `assert files != []` (clear "run mix deps.get" message).
- Per file: `for issue <- Credence.Pattern.analyze(File.read!(path)),
  issue.rule != :parse_error, do: {path, issue}`.
- `assert findings == []` with a message listing `package`, `path:line`
  (`issue.meta[:line]`), `issue.rule`, and the offending source line — actionable for
  triage.
- Note: runs the **default-enabled** rule set (matches what ships); assumption-gated rules
  aren't exercised unless opts widened — fine, they don't fire for users either.

## Files
- `mix.exs` — add 9 `only: :test, runtime: false` deps to `deps/0`.
- `mix.lock` — regenerated by `mix deps.get`.
- `test/corpus/over_firing_test.exs` — the whole layer (new).

## Reuse (don't reinvent)
- `Credence.Pattern.analyze/2` — `lib/pattern.ex:14` (the only Credence call needed).
- `Credence.Issue` `.rule` / `.meta[:line]` — `lib/issue.ex` (reporting).

## Tooling — reusable mix tasks (replaces the throwaway /tmp scripts)
- `Credence.Corpus` (`lib/credence/corpus.ex`) — pinned `{pkg, version}` list, `lib_files/1`,
  `fetched?/1`, idempotent `ensure_fetched!/0` (shells `mix hex.package fetch`). Single source
  shared by the test AND the tasks (moved here from `test/support/`).
- `mix credence.corpus.fetch` — populate `corpus/` (idempotent; skips warm pins).
- `mix credence.corpus` — summary: total findings, crashes, counts by rule + by package.
- `mix credence.corpus <rule>` — every occurrence of `<rule>` with `file:line` + source line.
  A *crash* (a rule raising on valid code) is reported separately — fix those first.
  Reports RAW findings; the over-firing test additionally allowlists reviewed-legit rules.
- These supersede the ad-hoc `/tmp/*.exs` probes; use them in future sessions / the loop.

## Verification / rollout
1. `mix deps.get` — fetch the 10 packages once.
2. `mix test test/corpus/over_firing_test.exs` — observe findings.
3. **Expect the first run to surface real findings** (popular code does contain patterns
   the 170 rules target). The harness is green only once every shipped rule is clean on the
   corpus. Reconciliation = narrow each over-firing rule (existing methodology) — the
   intended ongoing use, separate from building the harness.
4. `mix test` — confirm the layer runs in the default suite and total runtime stays in the
   ~15-20s range (parse-only).

## Resolved during implementation
- **Q1 Fetch mechanism → `mix hex.package fetch` into a gitignored `corpus/` dir.**
  Verified: `mix hex.package fetch PACKAGE [VERSION] [--unpack] [--output PATH]` exists,
  works over network, fetches **only** the named package source (no transitive deps, no
  compilation). For parse-only scope we never need compiled artifacts, so this is strictly
  nimbler than mix-deps (which would compile phoenix/ecto/credo + ~40 transitive packages
  on first build, and make the linter falsely "depend on" phoenix/ecto). Pins: exact
  version string per package (hex versions are immutable + checksum-verified on fetch), not
  `mix.lock`. Cache at `corpus/` (gitignored, survives `mix clean`, fetched once, reused by
  the loop). `/tmp/` and `/deps/` are gitignored but unsuitable (wiped / mix-managed).

## Findings (measured 2026-06-13)
Corpus = 552 `lib/*.ex` files. `Credence.Pattern.analyze` over all of them ran in
**5.4s**, **0 parse errors**, **1760 findings** (default-enabled rules).

Pinned versions (latest stable at fetch): jason 1.4.5, plug 1.19.2, ecto 3.14.0,
phoenix 1.8.8, decimal 3.1.1, gettext 1.0.2, poison 6.0.0, tesla 1.20.0, floki 0.38.3,
credo 1.7.19.

Top firing rules:
| count | rule |
|------:|------|
| 978 | avoid_rebinding_parameter |
| 224 | remove_unreachable_clauses_after_catchall |
| 113 | inconsistent_param_names |
|  84 | no_param_rebinding |
|  61 | no_kernel_shadowing |
|  39 | no_duplicate_spec |
|  39 | no_duplicate_function_clauses |
|  33 | non_grouped_clauses |
|  22 | no_case_true_false |
|  19 | no_recursive_case_without_empty_list_clause |
| ... | (~38 more rules, long tail down to 1) |

By package: ecto 683, credo 301, phoenix 194, plug 146, tesla 133, floki 103, jason 69,
gettext 62, poison 36, decimal 33.

Spot-check (ground truth):
- `avoid_rebinding_parameter` fires on ubiquitous idiom: `key = IO.iodata_to_binary(...)`
  (rebinds param), `[acc | stack] = stack`. Everyday Elixir → opinionated or over-firing.
- `remove_unreachable_clauses_after_catchall` flags clauses that look **reachable**
  (`def decode_each({key, value}, map)` after `{"", value}`; guarded `def code(integer)
  when integer in 100..999`). If its fix deletes these it would remove live code — a
  likely real over-fire **bug**, highest-priority to verify.

### Q2 resolved by data → tag `@moduletag :corpus`, **excluded by default**.
1760 findings makes strict-zero-in-main-suite permanently red, which breaks the evolution
loop (promote stages gate on green `mix test`). So the harness lands excluded
(`ExUnit.configure(exclude: [:corpus])` in `test_helper.exs`); run it with
`mix test --include corpus`. Strict-zero is preserved (not a baseline — user chose
strict-zero); the path to flipping it into the default suite is **narrowing the
over-firing rules** until findings reach 0, per the methodology. This honors strict-zero
without breaking the loop.

## Triage of the 1760 findings (complete)
A fan-out workflow (63 agents: one triage per firing rule + adversarial verification of every
BUG verdict) classified all 50 firing rules. Tally: **13 BUG · 18 OVERFIRE_OPINIONATED ·
17 LEGIT · 2 MIXED**. All 13 BUG verdicts survived adversarial re-checking. The corpus layer
paid off immediately: it found **13 real over-fire bugs in shipped rules**, 12 of them `[high]`
severity (the auto-fix deletes or alters correct code, and the compile-gate does NOT catch it
because the corrupted code still compiles — it just changes runtime behavior).

### Confirmed BUGs (13) — prioritized; do NOT auto-edit shipped rules without maintainer sign-off
| count | sev | rule | root cause / why it's a false positive | fix direction |
|------:|-----|------|------|------|
| 224 | high | `remove_unreachable_clauses_after_catchall` | `catch_all?` calls any all-bare-var/no-guard head a catch-all — ignores **non-linear patterns** (`traverse(ref, ref)`, `split_key(_b, start, start)`) and **bodiless heads** (`def code(integer_or_atom)`); fix deletes reachable clauses → FunctionClauseError | exclude repeated-arg-var heads + bodiless heads from `catch_all?` |
| 39 | high | `no_duplicate_spec` | keys duplicates on function **name only, ignoring arity** — flags `send_resp/1` vs `/3` as dupes | key on `{name, arity}` |
| 39 | high | `no_duplicate_function_clauses` | same non-linear-pattern + bodiless-head blindness as #1 (normalize_ast erases repeated-var identity); fix deletes the real catch-all | track repeated vars; drop bodiless heads; disable fix until then |
| 33 | high | `non_grouped_clauses` | ignores **macro-generated clauses** (`for`/`Enum.map` blocks that emit `def`s) → false "ungrouped"; fix **reorders** clauses, moving a catch-all ahead of generated clauses → behavior change | treat clause-generating macro blocks as transparent to grouping; gate/drop fix |
| 19 | high | `no_recursive_case_without_empty_list_clause` | no notion of a catch-all (`_ ->`) that already covers `[]`; fix prepends a **fabricated** `[] -> {...}` body | skip when a catch-all subsumes `[]`; make check-only |
| 13 | high | `no_defensive_type_guard_clause` | deletes `when not is_*` clauses that are real **dispatch guards** (raise / return distinct branch), not redundant | narrow to non-raising redundant clause w/ behavior-identical fall-through |
| 12 | high | `no_unnecessary_catch_all_raise` | deletes reachable terminal clauses raising **domain-specific** errors (and in ecto, the only `doc!/1` def behind 49 callers → won't compile) | require ≥1 sibling clause + no refining preceding clauses + generic error |
| 3 | med | `no_missing_require_logger` | checks `require Logger` only at top level but finds Logger calls in nested/quote scope → false "missing"; fix injects dead/duplicate require | match require scope to call scope; don't descend into quote |
| 3 | high | `no_redundant_local_capture` | fires on bare `var = &f/n` **without** verifying the paired `var.(args)` call; fix deletes a still-referenced binding → won't compile | require the paired application before firing |
| 3 | high | `prefer_negate_if_true_false` | fix renders multi-line `do/else/end` into a **single-line/interpolated** `if` inside a heredoc → unparseable | skip single-line/interpolated `if`; only rewrite block form |
| 1 | high | `no_map_keys_or_values_for_iteration` | fix under-covers a complex `&(...)` capture's closing paren → non-compiling | fix patch range to cover full capture |
| 1 | high | `prefer_no_question_mark_for_non_boolean` | renames a **public** API fn (`Ecto.Multi.exists?/4`) → breaking change; leaves `@doc`/`c:Mod.fun?` refs dangling | never auto-rename public defs; exclude wrapper/builder idioms |
| 1 | high | `no_unused_computation` | classifies `Enum.each` as **pure** (it's the canonical side-effect iterator); fix deletes load-bearing validation | remove `:each` from pure allowlist; exclude HOF calls that can raise |

**Cross-cutting root cause:** three clause-analysis rules (#1, #3 `no_duplicate_function_clauses`,
and the grouping rule `non_grouped_clauses`) share the same blind spots — **non-linear
(repeated-variable) patterns** and **bodiless function heads**. A shared clause-classifier fix
(or helper) would address all three. (See [[rules-stay-self-contained]] re: whether to extract.)

### OVERFIRE_OPINIONATED (18) — premise true, but flags correct idiomatic code
Dominated by `avoid_rebinding_parameter` (978) — flags everyday `key = transform(key)` /
`[acc | rest] = rest`. Others: `inconsistent_param_names` (113), `no_param_rebinding` (84),
`no_kernel_shadowing` (61), `no_case_true_false` (22), `prefer_map_new` (18), `prefer_guard_over_if`
(10), `prefer_explicit_binary_arithmetic` (10), + long tail. These are style stances — the
maintainer decides per rule: demote to opt-in / narrow / keep. Two have **unsafe fixes** despite
being "opinionated": `no_kernel_shadowing` (61) and `no_case_true_false` (22) can change behavior
(fix scope / non-boolean subject) — narrow the fix before trusting it. Also `avoid_rebinding_parameter`
has a check/fix **asymmetry**: `check` fires on rebinds nested in if/case/macro `->` clauses, but
the fix only rewrites top-level block exprs → many fires are unfixable noise.

### MIXED (2)
- `no_find_value_default_case` (3): detection right, but the `||`→`find_value/3`-default fix turns
  a lazy short-circuit default into an **eagerly-evaluated** argument — unsafe (cf.
  [[find-vs-find-value-default-safety]]).
- `no_guard_equality_for_pattern_match` (4): 3 legit (credo), 1 not.

### LEGIT (17)
Small counts (`no_redundant_assignment` 9, `no_case_boolean_result` 6, `use_map_join` 5, …) where
the flagged code genuinely matches the target pattern — these are real, correct suggestions, not
over-fires. Full per-rule detail in the workflow result (`tasks/wm764uvxh.output`,
`.result[]`); confirmed-bug detail also in `/tmp/bugs_detail.txt`.

## Post-pull re-measure (after `git pull` — evolution ran in parallel, +17 commits)
Re-ran the corpus against the updated rules: **1775 findings + 36 files that CRASH** the
analyzer. Evolution modified some flagged rules and added new firing ones. Current top:
avoid_rebinding_parameter 903, remove_unreachable_clauses_after_catchall **205** (still
buggy), prefer_private_helpers **115 (NEW)**, inconsistent_param_names 105, no_param_rebinding
84, no_kernel_shadowing 55, no_duplicate_function_clauses 34, non_grouped_clauses 31,
no_duplicate_spec 31, prefer_remove_unused_private_fn_param **29 (NEW + crashes)**,
no_if_boolean_result **13 (NEW)**, …

**NEW crash bug (most urgent):** `prefer_remove_unused_private_fn_param` raises
`:erlang.length(nil)` in `find_unused_param_indices/1` on 36 corpus files — a rule that
*crashes* `Credence.analyze` on valid code (worse than a false positive).

Decision: per maintainer, **fix ALL over-firing rules**. Working through them in priority
order (crash → confirmed bugs → opinionated), re-measuring the corpus after each.

### Fix progress (corpus total, re-measured after each)
- ✅ `prefer_remove_unused_private_fn_param` crash — `find_unused_param_indices` did
  `hd(args)|>length` on a zero-arity `defp` (`nil` args) and `0..(arity-1)` became `0..-1`;
  guarded both + added `is_list` to `extract_defp_args`. **36 crashing files → 0.**
- ✅ `remove_unreachable_clauses_after_catchall` (205→0): narrowed `catch_all?` to reject
  repeated-variable (non-linear) heads + excluded bodiless heads from clause collection.
  +2 regression tests. **Total 1936 → 1712.**
- ✅ `no_duplicate_function_clauses` (34→3): replaced the all-vars-→-`:_var` normalizer
  with a stateful one preserving repeated-variable identity (`f(x,x)` ≠ `f(a,b)`); excluded
  bodiless heads. **Total → ~1670.**
- ✅ `no_duplicate_spec` (39→3): key duplicates on `{name, arity}`, not name alone
  (`send_resp/1` ≠ `send_resp/3`). **Total 1712 → 1640.**
- ✅ `non_grouped_clauses` (33→1): clause-generating macro blocks (`for ... do def end`)
  are now transparent to grouping (Elixir emits no warning across macro-generated clauses);
  fixes both the false flag and the behavior-changing reorder.
- ✅ `no_recursive_case_without_empty_list_clause` (19→2): don't fire when an unguarded
  catch-all clause (`_ ->` / bare var) already covers `[]`.
- **Total 1936 → 1591. Full suite: 5470 tests, 0 failures** (corpus excluded).
- Bugs done: crash + 6 highest-impact (the code-deleting / code-corrupting ones).
- Regression tests added for remove_unreachable; pending for the other 5 (existing per-rule
  suites still pass).

### Opinionated rules — going through one-by-one (maintainer deciding each)
- ✅ `avoid_rebinding_parameter` (978) → **DROPPED** (rule + 3 test files deleted). Fired
  entirely on idiomatic Elixir — `opts = Keyword.validate!(opts, …)`, `conn = …` threading,
  param coercion (`uri = URI.parse(uri)`), accumulator threading. No salvageable narrower
  core; its fix would rename `opts`→`opts_opt`. **Total 1591 → 613. Suite 5458 tests, 0 failures.**

- ✅ `prefer_private_helpers` (128 → 44) → **NARROWED** (maintainer choice). Flagged real
  public API (`Jason.decode/2`, `Floki.attr/4`, `Gettext.get_locale/1`, …) because
  single-module analysis can't see external callers; its fix would `defp` them = breaking
  change. Now skips functions with a real `@doc` (only fires on `@spec`-only / `@doc false`).
  Rule + both test files + moduledoc updated. **Total 529. Residual 44** may still include
  cross-module-public `@spec`-only fns (known limit; accepted as partial fix).

- ✅ `inconsistent_param_names` (113 → 41) → **NARROWED** (maintainer choice). Fired on
  intentional guard-differentiated naming (`keywords`/`check_mod`, `elems`/`elem`,
  `html_elem_tuple`/`html_tree_list`) where the name reflects the type a guard proves; its
  fix made names lie (`is_list(map)`). Now skips any position whose variable is the subject
  of a type-check guard (`is_list`/`is_tuple`/…) in some clause — preserves genuine
  no-guard / comparison-guard drift detection (fibonacci, loop). Rule + 2 failing tests
  updated. **Total 457.** Residual 41 = non-type-guarded naming differences.

- ✅ `no_param_rebinding` (84) → **DROPPED** (maintainer choice). The `fn`-scope twin of
  `avoid_rebinding_parameter`; fired on reduce-accumulator threading, Agent/GenServer state
  transforms, param coercion — all idiomatic. Rule + 3 test files deleted. **Total 373.**

- ✅ `no_kernel_shadowing` (61) → **DROPPED** (maintainer choice). Flagged readable
  variable names (`length = byte_size(...)`, `{elem, attrs, children}`, `[_hd | tl]`) that
  happen to match Kernel fns; shadowing is valid/harmless and the fix is cosmetic churn.
  Rule + 3 test files deleted. **Total 312.**

- ✅ `prefer_remove_unused_private_fn_param` (32 → 0) → **NARROWED** (maintainer choice).
  Every corpus finding was on an intentionally-`_`-prefixed param; also had a non-linear
  head-pattern bug (`pop_ordered(pk, [pk | tail])`). Now exempts `_`-prefixed params and
  params reused in another arg's pattern. Rule + moduledoc + both test files + equivalence
  test updated. **Total 280.** (Crash was fixed earlier; this is the over-fire narrowing.)

Running tally: **1936 → 280** (crash + 5 bug fixes; dropped avoid_rebinding_parameter,
no_param_rebinding, no_kernel_shadowing; narrowed prefer_private_helpers,
inconsistent_param_names, prefer_remove_unused_private_fn_param). Full suite green
throughout (5417 tests).

- ✅ `no_case_true_false` (22 → 13) → **NARROWED** (maintainer choice). Fired on
  non-boolean subjects (`opts[:encode]`, opaque calls) where `case`→`if` changes behavior
  (case raises on non-boolean; if treats truthy). Now requires a provably-boolean subject
  (comparison / and·or·not·in / `is_*` / `?`-predicate calls / pipe ending in one). Rule +
  4 tests updated. Residual 13 are genuine boolean-subject cases (legit). **Total 271.**
- ✅ `prefer_map_new` (18) → **ACCEPTED as legit** (maintainer choice). All findings are the
  safe `Enum.into(x, %{})` → `Map.new(x)` upgrade. Added an explicit, commented
  `@accepted_legit_rules` allowlist to the corpus test (verified the filter excludes it).
  Policy: correct rules that fire on genuinely-improvable code are allowlisted (reviewed
  one-by-one), so the corpus guards only true over-firing.

- ✅ `no_if_boolean_result` (15 → 12) → **NARROWED + allowlisted** (maintainer choice).
  `if cond do true else x end` → `cond or x` raises BadBooleanError when `cond` is
  non-boolean (`a && b`, plain vars). Now requires a provably-boolean condition (same logic
  as no_case_true_false; duplicated per [[rules-stay-self-contained]]). Residual 12 are safe
  legit simplifications → added to the corpus allowlist. Rule + 6 tests updated. Raw 268.

- ✅ `no_defensive_type_guard_clause` (13) → **DROPPED** (maintainer choice). Deleted
  `when not is_type(x)` clauses that raise precise errors / dispatch / are the *sole*
  implementation (would delete `Ecto.Changeset.validate_required/3`). Unsound premise
  (removal changes behavior, even in its own moduledoc example). Rule + 3 test files
  deleted. Raw 255.

- ✅ `no_unnecessary_catch_all_raise` (12) → **DROPPED** (maintainer choice). Same unsound
  premise; deleted sole-clause `doc!/1` (compile break), validation `!`-functions, and
  precise-error catch-alls (`socket_ref`, `CSS.escape`). Rule + 3 test files deleted.
  Suite 5374 tests, 0 failures. Raw ~243.

- ✅ `prefer_guard_over_if` (10) → **kept + allowlisted** (legit style: if/else-body →
  guard clauses, behavior-preserving).
- ✅ `prefer_explicit_binary_arithmetic` (10 → 6) → **NARROWED to single pipe + allowlisted**
  (maintainer choice). Was flagging div/rem steps inside pipe chains
  (`diff |> div(1000) |> Integer.to_string()`); now only a standalone `x |> div(n)`.
  Rule updated (check + fix share `chained_arith_pipes`/`standalone?`); 20 tests pass.

### Tally after rule-by-rule pass (so far)
Raw corpus **1936 → 239**; the corpus test allowlists 46 verified-legit findings
(prefer_map_new 18, no_if_boolean_result 12, prefer_guard_over_if 10,
prefer_explicit_binary_arithmetic 6), so it now flags ~193 — dominated by the two
**narrowed residuals** `prefer_private_helpers` (44) + `inconsistent_param_names` (41).
Full suite green throughout (5374 tests). ~22 small rules (≤9 each) remain to triage.

- ✅ `no_redundant_assignment` (9 → 6) → **NARROWED to single var + allowlisted**
  (maintainer choice). Tuple/list forms (`{a, b} = f(); {a, b}`) dropped — collapsing them
  discards the match's arity assertion. Rule + moduledoc + 8 tests updated. Simple-var
  residual allowlisted (100% behavior-preserving).

- ✅ `no_case_boolean_result` (6) → kept + allowlisted (legit `case → match?/2`).
- ✅ `no_case_on_param_dispatch` (5) → kept + allowlisted (legit style, behavior-preserving).
- ✅ `no_enum_drop_negative` (5) → **DROPPED** (idiomatic `Enum.drop(list, -1)`; rewrite to
  `Enum.slice` gives no perf gain and is less readable).
- ✅ `use_map_join` (5) → kept + allowlisted (perf+idiom win). Suite 5355 tests, 0 failures.

Allowlist so far (8): prefer_map_new, no_if_boolean_result, prefer_guard_over_if,
prefer_explicit_binary_arithmetic, no_redundant_assignment, no_case_boolean_result,
no_case_on_param_dispatch, use_map_join.

- ✅ `no_doc_false_on_private` (4), `no_enum_count_for_length` (4) → kept + allowlisted (legit).
- ✅ `no_guard_equality_for_pattern_match` (4 → 3) → NARROWED (no extraction from `or`
  disjunctions) + allowlisted; 2 tests inverted.
- ✅ `no_find_value_default_case` (3 → 1) → NARROWED to eager-safe defaults (excludes
  `|| raise …`, which lazy→eager would always-raise) + allowlisted the safe ecto case.
- ✅ `no_missing_require_logger` (3 → 0) → **BUG FIXED** (no allowlist needed). Recognizes
  `require Logger` co-located in a function body or inside a `quote`; skips `quote` blocks
  when scanning for calls. 45 tests pass.

Allowlist now 12 rules. Raw corpus 225. Full suite 5355 tests, 0 failures.

### Rule-by-rule pass, part 2 (toward green so the corpus can join `mix test`)
- ✅ `no_list_fold` → **SPLIT**: new `no_list_foldl` (foldl→reduce, clean; allowlisted) +
  `foldr` dropped. New rule + 3 tests; old rule + 3 tests deleted. 14 tests pass.
- ✅ `no_redundant_local_capture` (3 → 0) → **BUG FIXED** (scope analysis): fires only when the
  captured var is used exclusively via `var.(args)` (matching arity), never as a value. 9 tests.
- ✅ `prefer_negate_if_true_false` (3 → 2) → **NARROWED** to block-form `if` (skip keyword/
  interpolated forms the multi-line rewrite corrupts) + allowlisted the 2 safe rewrites.
- ✅ `prefer_private_helpers` (44) → **DROPPED**. Residual was mostly cross-module-public
  functions (Decimal.Context.get, Ecto.Type.adapter_load/dump, Floki.Finder.find) wrongly
  flagged — single-module analysis can't see external callers, so it can't be safe by
  default for any multi-module library. Rule + 3 test files deleted. **Raw total 174.**

- ✅ `no_redundant_local_capture` (3→0, bug fixed), `prefer_negate_if_true_false` (3→2,
  narrowed+allowlisted), `prefer_private_helpers` (44 DROPPED — cross-module-public),
  `inconsistent_param_names` (41 DROPPED — intentional dispatch-naming).
- ✅ `no_duplicate_spec` (3→0): key on full spec text (overloaded specs ≠ duplicates).
  `no_duplicate_function_clauses` (3→1): normalizer no longer collapses module-attribute
  names; the 1 residual is a genuine unreachable clause (ecto escape/5 539 vs 558) →
  allowlisted. Both were completions of the earlier approved "fix". Suite 5243 tests.

### Remaining work (needs maintainer direction)
- **~7 nuanced/smaller bugs**: no_defensive_type_guard_clause (13), no_unnecessary_catch_all_raise
  (12), no_missing_require_logger (3), no_redundant_local_capture (3), prefer_negate_if_true_false
  (2), no_map_keys_or_values_for_iteration (1), prefer_no_question_mark_for_non_boolean (1),
  no_unused_computation (1). Several are borderline — triage recommends narrow-to-check-only
  or retire (their fixes change behavior even on correct code).
- **4 NEW rules from evolution, untriaged**: prefer_private_helpers (115!), prefer_remove_unused_private_fn_param
  (29, crash fixed), no_if_boolean_result (13), prefer_cond_for_nested_if (1).
- **~18 OPINIONATED rules (~1300 findings, the bulk)**: avoid_rebinding_parameter (903),
  inconsistent_param_names (105), no_param_rebinding (84), no_kernel_shadowing (55),
  no_case_true_false (21), prefer_map_new (18), … These fire on idiomatic code *by design*;
  reaching strict-zero requires a product decision (narrow / demote-to-opt-in / drop).

> Note on residuals: the duplicate rules still show 3 each — likely other shapes or genuine
> dupes; revisit after the breadth pass.

> **Reaching strict-zero green requires a decision on the ~18 OPINIONATED rules**
> (avoid_rebinding_parameter 903, inconsistent_param_names 105, …). They fire on idiomatic
> code *by design*, so "fixing" them means narrowing or demoting to opt-in (via the
> assumptions mechanism) — a product call, surfaced at the end of the bug pass.

## Recommended next steps (maintainer's call — not auto-applied)
1. **Fix the 13 bugs** (start with the high-count/high-sev: `remove_unreachable_clauses_after_catchall`,
   `no_duplicate_function_clauses`, `non_grouped_clauses`, `no_duplicate_spec`). Several should be
   demoted to check-only / fix-disabled until narrowed, per the methodology
   ([[rule-evolution-methodology]]). Each fix needs its `_check_test` + `_fix_test`
   ([[rule-test-style]]) updated and the corpus finding count to drop.
2. **Decide the 18 opinionated rules** — narrow, demote to opt-in, or keep.
3. **Re-run** `mix test --include corpus` after each change; when findings reach 0, drop the
   `:corpus` exclude in `test_helper.exs` to promote the layer into the default suite.

## Final status (2026-06-13) — corpus promoted into `mix test`

Reconciliation is complete. The corpus over-firing layer runs in the default suite
(`test_helper.exs` no longer excludes `:corpus`); `mix test` is **5157 tests, 0 failures**,
including the 10 corpus tests. Verified: `mix test test/corpus/over_firing_test.exs` (no
`--include`) → 10 tests, 0 failures.

### The last 3 confirmed BUGs — all fixed (strictly one-by-one)
- ✅ `no_unused_computation` (1→0) — **NARROWED**. Removed `:each` from the pure-fn allowlist
  and added `any_fun_arg?/1`: a call carrying a function literal/capture (`&f/1`, `fn …`) is
  never discardable (the function can raise / have side effects), so it no longer deletes
  load-bearing work like `_ = Enum.each(keys, &cast!/1)`. 20 tests.
- ✅ `no_map_keys_or_values_for_iteration` (1, kept + allowlisted) — **FIX BUG FIXED**.
  Sourceror's `get_range` under-reports a parenthesized `&(…)` capture whose body ends in a
  nested call (no closing-paren metadata on the `&` node) → the rewrite orphaned the wrapping
  `)`. Added `correct_capture_range/2`, which paren-matches the `&(` in the source and extends
  the patch. Detection is sound and the rewrite (order-independent `any?`/`all?`/… only) is
  behaviour-preserving, so it's allowlisted. +1 regression test (capture-ending-in-call). 111 tests.
- ✅ `prefer_no_question_mark_for_non_boolean` (1→0) — **NARROWED to `defp` only**. Renaming a
  public `def` is a breaking API change and can't reach external `@doc`/`c:Mod.fun?` refs (e.g.
  `Ecto.Multi.exists?/4` mirrors `Repo.exists?`). Now flags only private helpers whose call
  sites all live in-module (`private_only_names/1`). 14 tests.

### Stale golden tests updated (collateral from earlier rule drops)
Dropping `no_enum_at_negative_index`, `no_is_prefix_for_non_guard`, and
`prefer_pattern_match_over_if_empty_list` earlier in the session left three integration
goldens pinning transformations those rules used to make. Re-pinned to current `Credence.fix`
output (verified idiomatic): `test/fix_showcase_test.exs`, `test/credence_test.exs` (showcase),
`test/fix_examples_test.exs` (Examples 1–4).

### Allowlist (`@accepted_legit_rules`, 34 rules)
Every rule that still fires on the corpus is a reviewed, behaviour-preserving suggestion —
listed with its rationale in `test/corpus/over_firing_test.exs`. A rule is added there only
after its corpus findings are individually verified safe; everything else was fixed, narrowed,
or dropped. New over-firing on idiomatic real code now goes red immediately under `mix test`.

## Snapshot ratchet (replaces the rule-level allowlist)

A whole-rule allowlist is too blunt: once `prefer_map_new` is accepted, it can start firing on
genuinely-broken *new* code and the test stays green. Replaced with a per-finding snapshot.

- **`lib/credence/corpus/findings.ex`** (`Credence.Corpus.Findings`) — formats every Pattern
  finding as a stable identity `"<corpus-relative path>:<line>  <rule>"`, collapsing the rare
  exact duplicate (same file+line+rule) with a trailing `(xN)`. The line comes straight from
  the issue, so there is no AST resolution; `format/1` is public and unit-tested
  (`test/corpus/findings_test.exs`).
- **`test/corpus/accepted_findings.txt`** — the committed snapshot (120 lines). Regenerate with
  `mix credence.corpus --update-snapshot`.
- **`test/corpus/over_firing_test.exs`** — per package, asserts the live identity set equals
  the snapshot's lines for that package. A **NEW** line ⇒ candidate over-fire (red, listed
  under "NEW — investigate!"); a **GONE** line ⇒ a rule narrowed/was removed (red, re-pin).

**Granularity = `file:line`** (chosen for maximal sensitivity). Every finding is distinct, so
*any* new firing site is a diff — including one inside an already-pinned function, which a
coarser `Module.fun/arity` key would mask on a count-preserving swap. The cost is that bumping
a package version shifts line numbers and forces a re-pin (intended: re-review on upgrade).
An earlier `Module.fun/arity` variant existed (with an AST resolver + adversarial-review fixes
for `defmacro`/`defguard` and `Sourceror.get_range` end-lines) but was dropped in favour of
this simpler, stricter `file:line` key.

Verified: deterministic across runs; catches an injected new finding (NEW) and a vanished one
(GONE); `format/1` unit-tested (line format, `(xN)` collapse, distinct-line separation,
nil-line `:?` placeholder, sort). One finding pins as `…forbidden_module.ex:?` because
`prefer_map_new_with_transform` emits no line metadata for it — a minor rule gap, stable as-is.
