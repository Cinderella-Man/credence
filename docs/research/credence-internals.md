> **Provenance & verification status (added 2026-07-11 by the coordinating
> session before hand-off).** Produced by an autonomous research agent (Claude
> Opus); subsequently updated where the implementation has moved on. The
> current tree runs compilation in a heap- and timeout-bounded child process,
> and the Semantic round re-measures every changed pass and reverts attributable
> regressions. The analyze/fix desync on the patch self-revert
> path (`lib/rule_helpers.ex:279` — the code comment itself documents
> "reported, just goes unfixed"), and the corpus test structure. Two later
> refinements from `docs/13`/`docs/14`: `discover_rules` measures 0.24 ms warm
> (so §6.2's memoization concern is minor), and §6.2's cost model was
> quantified precisely (parse ~8–14 ms/file, full analyze ~53 ms/file on real
> corpus files). Direct line-count of the whitelist gives 6,138 non-comment
> lines (§6.8 says 6,137 — immaterial). §1.5's compile-count formula and §6.6's
> desync are the two facts most load-bearing for the proposals in docs/12.

---

# Credence internals — pipeline, framework, QA, tooling, docs, weaknesses

Read-only research report. All paths absolute-relative to `/home/kamil/projects/credence`.
Every claim cites `file:line`. Rule-level quality is out of scope (another agent); this is
pipeline/architecture-level.

Scale snapshot (updated 2026-08-30): **160 Pattern rules** (`lib/pattern/*.ex` minus `rule.ex`),
**92 Semantic rules** (`lib/semantic/*.ex` minus `rule.ex`), **48 Syntax rules** (`lib/syntax/*.ex` minus
`rule.ex`). Version 0.8.1 (`mix.exs:7`). Sole parse/patch dependency: `sourceror ~> 1.11`
(`mix.exs:39`; lock is 1.12.0).

---

## 1. PIPELINE MECHANICS

### 1.1 Top-level entry (`lib/credence.ex`)

- `Credence.analyze/2` (`lib/credence.ex:26-38`): runs `Syntax.analyze` first
  (`:27`); **if any syntax issue exists it returns immediately** with `valid: false`
  (`:29-30`) and never runs Semantic/Pattern. Otherwise runs `Semantic.analyze` +
  `Pattern.analyze` and concatenates (`:32-36`). So a file that does not parse reports
  only syntax issues — semantic/pattern findings are masked until it parses.
- `Credence.fix/2` (`lib/credence.ex:45-58`): strictly sequential, each phase once:
  `Syntax.fix_with_trace` → `Semantic.fix_with_trace` → `Pattern.fix_with_trace`
  (`:47-53`), concatenates the three traces (`:55`), then calls `analyze(fixed, ...)`
  once more (`:56`) to compute the `issues:` still remaining. Return shape:
  `%{code, issues, applied_rules}` where `applied_rules :: [{module(), non_neg_integer() | :reverted}]`
  (`:40-44`, `:57`). **There is no outer fixpoint loop across phases** — the pipeline runs
  each phase exactly once.
- `rule_status/1` (`:82-86`) and `enabled_rules/1` (`:107-109`) are opts-only views;
  Syntax/Semantic entries are always `enabled: true, assumptions: [], missing: []`
  (`:88-99`) — only Pattern is opts-filtered. The moduledoc explicitly warns this
  over-reports: whether a rule *actually fires* depends on the code (`:76-79`).

### 1.2 Pattern round (`lib/pattern.ex`) — single pass, priority order

- Rule discovery + ordering: `default_rules/0` → `RuleHelpers.discover_rules(Credence.Pattern.Rule)`
  (`lib/pattern.ex:165-167`), which is `Application.spec(:credence, :modules)` filtered by
  `@behaviour` and **sorted by `{priority(), module}`** (`lib/rule_helpers.ex:20-24`). Lower
  priority first; module name (alphabetical) is the deterministic tiebreaker.
- `analyze/2` (`:14-24`): `Sourceror.parse_string` once; on `{:ok, ast}` runs
  `reject_dsl_unfixable/3` per rule and `flat_map`s issues (`:19`); on parse error returns a
  single `:parse_error` issue (`:21-22`, `:217-231`). **No compilation in Pattern.analyze —
  parse-only.**
- `fix_with_trace/2` (`:64-76`): computes `rules(opts)`, then **gates the whole round on
  `RuleHelpers.compiles?(code_string)`** (`:69`) — if the source does not compile, the entire
  Pattern round is skipped and returns `{code_string, []}` (`:70-75`). Rationale in the
  docstring (`:57-60`): AST transforms on semantically-invalid code risk new errors.
- `run_fixable_rules/3` (`:78-116`) is the core. It is a **single `Enum.reduce` over the
  rules in priority order** (`:80`). Per rule iteration:
  1. `Sourceror.parse_string(source)` **freshly every iteration** (`:83`) — re-parsed for
     every one of the 160 rules regardless of whether the source changed.
  2. `rule.check(ast, check_opts)` (`:86`).
  3. if issues non-empty → `invoke_fix` = `RuleHelpers.apply_rule_fix` (`:93`, `:120`) →
     `apply_or_revert` (`:94`).
  4. else pass source through unchanged (`:96`).

**Answer to the fixed-point question: NO, the Pattern round is a single pass in priority
order, not a fixed-point loop.** If rule A's fix produces a shape that an
earlier-ordered rule B already ran past, **B does not get a second chance within this
`fix` call** — the reduce moves forward only. The only "loop" anywhere in the pipeline is
the Semantic round (§1.3), and it retries only on *errors*, not on newly-created patterns.
Convergence therefore depends on (a) each rule being individually idempotent and (b) no
rule creating work for an earlier-priority rule. See Weaknesses §6.1.

### 1.3 Semantic round (`lib/semantic.ex`) — bounded retry loop on errors only

- `@default_max_passes 3` (`:19`), overridable via `opts[:max_passes]` (`:53`).
- `analyze/2` (`:22-34`): `compile_and_capture`; on `{:ok, diags}` matches **warning-level**
  diagnostics, on `{:error, diags}` matches **error-level** diagnostics (`:24-33`).
- `do_fix_traced/4` (`:71-117`) is the pass loop:
  - Compilation **succeeds** → fix warnings, **terminal — no retry** (`:78-87`, comment
    `:79`). A warning fix that introduces a new warning is not re-fixed this phase.
  - Compilation **fails** → fix errors, and **retry** (`pass+1`) only if the source changed
    (`:89-115`). If no error fix changed the source, it stops (`:109-114`).
- `apply_fixes_traced/3`: sorts diagnostics **rightmost-column-first**
  (`Enum.sort_by(&position_sort_key/1, :desc)`, `:126`, `:160-166`) so column-aware fixes
  don't see stale columns after an earlier edit shifts the line (comment `:120-124`). For each
  diagnostic, `find_matching_rule` = first rule whose `match?/1` returns true (`:175-177`),
  then `rule.fix(src, diagnostic)`. A changed pass is recompiled and compared with its
  baseline health. Parse regressions, compile regressions, and strict additions to the error
  multiset with no repair are attributed to individual fixes; culpable fixes are reverted and
  recorded as `:reverted`. If attribution or replay is unsafe, the whole pass is reverted.
- Semantic rule ordering is also by `{priority(), module}`. The current override inventory is
  maintained in `docs/20-rule-ordering-policy.md`; first-match-wins dispatch makes those
  priorities ownership decisions, not merely presentation order.

### 1.4 Syntax round (`lib/syntax.ex`) — text fixes, only when unparseable, no revert

- `analyze/2` (`:16-21`): if `Sourceror.parse_string` succeeds returns `[]`; else `flat_map`
  each rule's `analyze/1` (`:19`).
- `fix_with_trace/2` (`:40-122`): if the source already parses, skip entirely (`:44-46`).
  Otherwise `Enum.reduce` over rules, each `rule.fix(src)` a **raw string→string transform**
  (`:71-83`); a change is logged but there is **no per-rule parse/compile revert**. After the
  reduce it re-parses once and only *logs* whether the source now parses (`:88-111`) — it does
  not undo a rule that made things worse. All 48 syntax rules use the default priority 500
  (`lib/syntax/rule.ex:23`), so order is purely alphabetical by module name.

### 1.5 How many compilations per `fix` call — and the cost

`RuleHelpers.compiles?/1` and `compile_and_capture/1` ultimately call **`Code.compile_string`**
in a heap- and timeout-bounded child process (a real compile that *executes module-body code*).
Per `Credence.fix` on a file that fires K Pattern rules:

- Syntax: parse-only (no compile).
- Semantic: 1 compile per pass, 1–3 passes (`lib/semantic.ex:77`).
- Pattern gate: **1 compile** (`lib/pattern.ex:69`).
- Pattern revert checks: **1 compile per firing rule** (`apply_or_revert` → `compiles?(fixed)`,
  `lib/pattern.ex:135`). So ~K compiles.
- Final `analyze`: **1 compile** (Semantic.analyze) (`lib/credence.ex:56`).

Total is `(1–3) + one changed-pass health check per Semantic pass + 1 + K + 1` full
compilations, with extra compiles only on the abnormal Semantic attribution path. Additionally,
per fix call the Pattern reduce does **160 `Sourceror.parse_string` calls** (one per rule) and
**160 `rule.check` AST prewalks**, plus the final `Pattern.analyze` does another 160 checks and
160 `dsl_dropped_ranges` calls. So `check` runs ~320 times per fix. `apply_rule_fix` on each firing rule additionally re-parses
(`Sourceror.parse_string!`, `lib/rule_helpers.ex:256`), runs `parses?` (`string_to_quoted`,
`:354-357`) and `comments_changed?` (`string_to_quoted_with_comments`, `:365-377`). See §6.2.

### 1.6 Patch application via Sourceror (`RuleHelpers.apply_rule_fix/3`, `lib/rule_helpers.ex:254-281`)

1. `opts` gets `:source` injected (`:255`); `Sourceror.parse_string!(source)` (`:256`).
2. `rule.fix_patches(ast, opts)` produces `[%{range, change}]`; `drop_dsl_patches` removes any
   patch landing in an `unsafe_in_dsl` block (`:258`, §1.7).
3. Empty patch list → source unchanged (`:259-260`).
4. Otherwise **all patches applied at once** via `Sourceror.patch_string(patches)` (`:265`),
   then `strip_trailing_ws_per_line` (`:266`, `:389-404`) normalizes only *inserted* lines
   (via a Myers diff) so pre-existing blank lines inside heredocs aren't mangled.
5. **Two self-revert guards** (`:279`): the fix is discarded (returns original `source`)
   unless the patched output `parses?` **and** `not comments_changed?`. Comment multiset must
   be identical (`:365-377`) — a fix that drops OR duplicates a comment self-reverts.

**Overlapping patches from one rule:** there is no explicit guard against a single rule
emitting two patches with overlapping ranges. The helper-built patches are non-overlapping
*by construction* — `diff_patches` emits patches at the *outermost* point of divergence
(`lib/rule_helpers.ex:529-614`, comment `:530-533`). But the ~40 rules that hand-build
patches (see §2.1) can in principle overlap; the only backstop is the parse/comment
self-revert in `apply_rule_fix` (`:279`), which discards the whole fix if the merged result
is invalid. So overlaps degrade to "finding reported, unfixed" rather than corrupt output —
but see §6.6 for the analyze/fix desync this creates.

### 1.7 Revert-on-broken-compile (`apply_or_revert/6`, `lib/pattern.ex:129-148`)

Three-way branch:
- `fixed == source` → "IDENTICAL source (no change)", not added to `applied` (`:131-133`).
- `not compiles?(fixed)` → **revert to pre-fix source**, mark `{rule, :reverted}` in the
  trace, log the broken diff (`:135-142`).
- otherwise → accept, record `{rule, length(issues)}` (`:144-146`).

So the revert mechanism is per-rule and post-fix: it compiles the candidate output, and on
failure keeps the previous good source while surfacing the offender as `:reverted`. This is
the Pattern round's per-rule compile-safety net. Semantic instead gates and attributes a whole
changed pass (§1.3), while Syntax has no equivalent (§1.4). Note there are effectively **two layers of self-protection** for
Pattern: (a) the parse+comment guard inside `apply_rule_fix` (`lib/rule_helpers.ex:279`, which
silently returns source), and (b) the compile guard in `apply_or_revert` (which marks
`:reverted`). Only (b) is visible in the trace.

### 1.8 DslGuard (`lib/dsl_guard.ex`) — detecting reinterpreting-macro regions

Purpose (moduledoc `:1-76`): some macros re-read plain Elixir AST with different meaning
(inside `Ash.Expr.expr/1` `!x` ≠ `not x`; `Ecto.Query` forbids `!`/`&&`/`== nil`; `Nx.Defn`
treats arithmetic/`if` as tensor ops). A rewrite valid in plain Elixir is wrong there and
still compiles, so it fails only at runtime.

- Families: `[:ash_expr, :ecto_query, :nx_defn]` (`:87-91`), plus `:custom` for
  user-configured macros.
- Detection is **mostly by call SHAPE, not by import** (moduledoc `:33-59`), because a
  parse-only tool can't expand `use MyAppWeb` wrappers. `block_ranges/2` (`:130-142`) prewalks
  the AST collecting blocks:
  - `expr(...)` always DSL (`@always_names ~w(expr)a`, `:96`).
  - `defn`/`defnp` bodies → `:nx_defn` (`:111`, `:290`).
  - `from(x in Y, ...)` → `:ecto_query` (recognized by first arg being an `_ in _`,
    `:291`,`:321-325`).
  - Ecto pipe macros (`where`, `select`, `join`, …, `@ecto_pipe_names` `:116-118`) only when a
    **binding-list arg** (`[p]`) that is *used as a binding*, or a **pin** (`^v`) is present
    (`:292`, `:349-351`, elaborate `uses_binding?`/`has_pin?` logic `:353-439`). This avoids
    misfiring on Explorer's `select(df, [column])`.
  - Qualified/aliased calls resolved through the file's alias table
    (`:298-318`, `alias_map/1` `:466-488`).
  - Ash's `filter`/`calculate`/`aggregate` (`@ash_signal_names`, `:107`) only when the file
    directly `import`/`use`s an `Ash.*` module (`ash_signal_names/1` `:500-516`) — the sole
    import-dependent path.
  - Extra names via `config :credence, dsl_macros:` or `opts[:dsl_macros]` (`:490-493`).
  - Function heads (`def dynamic(d)`) are excluded via `head_ids/1` (`:444-458`).
- Posture is **conservative** (moduledoc `:61-66`): when in doubt, treat as DSL — over-detection
  only costs a missed fix; under-detection ships a wrong one. Fail-safe: an unresolvable range
  degrades to a one-line meta-based range (`add_block`/`fallback_range` `:520-542`).

**Suppression, and why the two gates can't disagree.** Both gates derive from the *same*
`fix_patches` + `block_ranges`:
- Fix side (`RuleHelpers.drop_dsl_patches` → `dsl_partition`, `lib/rule_helpers.ex:287-344`):
  keep patches that don't intersect an unsafe-family block; `patch_blocked?`
  (`lib/dsl_guard.ex:196-222`) blocks any patch reaching *inside* a block, and allows a patch
  that *fully encloses* a block only if the block survives byte-for-byte in the replacement
  (`all_preserved?` `:239-250`).
- Analyze side (`Pattern.reject_dsl_unfixable`, `lib/pattern.ex:34-41`): computes
  `RuleHelpers.dsl_dropped_ranges` (`lib/rule_helpers.ex:304-325`) — the ranges of patches the
  fix *would drop* — and rejects any finding whose line falls in one (`DslGuard.line_in_ranges?`
  `lib/dsl_guard.ex:172-176`). A finding is reported iff its fix survives.
- Optimization: `dsl_dropped_ranges` short-circuits to `[]` for the ~9/10 rules that declare no
  `unsafe_in_dsl` families (`lib/rule_helpers.ex:310-312`), avoiding the `fix_patches`
  computation during analyze. The `fix_patches` call inside it is wrapped in try/rescue
  (`:316-320`).

---

## 2. RULE FRAMEWORK CONTRACTS

### 2.1 `Credence.Pattern.Rule` (`lib/pattern/rule.ex`)

Callbacks (`:52-86`):
- `priority() :: integer()` — default 500 (`:94`).
- `check(ast, opts) :: [Issue.t()]` — detect (`:55`).
- `fix_patches(ast, opts) :: [patch]` — emit byte-range patches; `[]` = no change (`:58`).
- `assumptions() :: [atom()]` — safety switches the fix needs; default `[]` (`:69`,`:97`).
- `unsafe_in_dsl() :: [atom()] | :all` — DSL families the fix is unsafe in; default `[]`
  (`:86`,`:100`).

`patch` type (`:47-50`): `%{required(:range) => map(), required(:change) => String.t()}`.
`__using__` injects `@behaviour`, `alias Credence.Issue`, and the three defaults, all
`defoverridable` (`:88-103`).

**Old `fix/2` callback is gone.** Per `docs/01`, the framework once had `fix(source,opts)` and
`fixable?/0`; the current behaviour has neither — every rule ships `fix_patches/2` (default via
`__using__`) and is fixable by construction. There is no warn-only mode (moduledoc `:5-7`).

Three fix-authoring styles (moduledoc `:26-38`), measured across `lib/pattern/`:
- `patches_from_postwalk/2` — 82 rules (single `Macro.postwalk` matcher).
- `patches_from_ast_transform/3` — 25 rules (prune/reorder/insert; re-parses rendered output).
- `patches_from_diff/2` — 1 rule.
- **Direct hand-built `%{range, change}` patches — ~40 rules** (grep: rules using none of the
  three helpers). These slice/emit ranges manually and are the highest-risk for range bugs
  (docs/09 records several: `no_anon_fn_application_in_pipe`, `no_map_keys_or_values_for_iteration`
  had Sourceror-range under-count bugs stranding a `)`).

Helper machinery in `lib/rule_helpers.ex`: `patches_from_postwalk` (`:477-480`),
`patches_from_diff` (`:494-496`), `patches_from_ast_transform` (`:514-527`), the AST-diff engine
`diff_patches`/`diff_patches_structural` (`:539-614`) which emits at outermost divergence and
handles `:__block__` sibling add/remove via Myers alignment (`aligned_patches`/`walk_ops`
`:628-699`), `render_replacement` (default `line_length: 98`, `:788-792`), plus comment-rescue
helpers `collect_comments`/`carry_comments` (`:827-869`) and `deletion_patch` (`:809-820`).

### 2.2 `Credence.Syntax.Rule` (`lib/syntax/rule.ex`) and `Credence.Semantic.Rule` (`lib/semantic/rule.ex`)

- Syntax: `priority/0` (default 500), `analyze(source) :: [Issue]`, `fix(source) :: source`
  (`lib/syntax/rule.ex:9-26`). Works on raw strings, no AST. `__using__` injects only
  `@behaviour` + default priority (no `Issue` alias — templates must add it, per docs/08).
- Semantic: `priority/0` (default 500), `match?(diagnostic)`, `to_issue(diagnostic)`,
  `fix(source, diagnostic)` (`lib/semantic/rule.ex:11-26`). Diagnostic shape
  `%{message, position: {line,col}|line, severity: :warning|:error}` (`:13-17`).

### 2.3 Priority distribution (collected)

Of 298 discovered rule modules, **18 rules declare a non-default priority**. The policy for
adding an override is in `docs/20-rule-ordering-policy.md`; the inventory below is refreshed from
the live dispatch lists because that policy document's adoption-time snapshot is now stale.

- **Pattern (160 rules):** 153 use the default 500. 7 override: `no_piped_regex_replace` = **50**
  (a repair rule for always-crashing `x |> Regex.replace(...)`, runs first,
  `lib/pattern/no_piped_regex_replace.ex:22`), `no_identity_function_in_enum` = 499,
  `no_explicit_sum_reduce`/`no_explicit_product_reduce`/`prefer_heredoc_for_multi_line_doc` = 501,
  `no_chunk_by_identity_for_dedup` = 510, `no_identity_enum_map` = 520. So priority is barely used
  as an ordering tool — **effective order is alphabetical by module name for ~95% of rules**.
- **Semantic (92):** 11 override: `missing_use_exunit_case` and
  `no_hallucinated_task_timeout_error_struct` = 100; `no_hallucinated_defpstruct`,
  `no_non_negated_integer`, and `no_stream_data_integer_two_args` = 400;
  `fix_reraise_keyword_in_catch` and `fix_truncated_special_form` = 450;
  `fix_local_function_in_guard` and `fix_negated_capture_with_arity` = 490;
  `undefined_function` and `no_unreachable_case_clause_by_type` = 501. The other 81 use 500.
- **Syntax (48 source files, 46 discovered rule modules):** all 500 → alphabetical.

### 2.4 `assumptions()` mechanism (`lib/assumptions.ex`, `lib/rule_helpers.ex`)

- Registry `@registry` (`lib/assumptions.ex:84-98`): exactly **two switches**,
  `single_codepoint_graphemes` (default on) and `proper_lists` (default on). `defaults/0`,
  `names/0`, `known?/1`, `validate!/1` (raises on unknown, `:121-132`).
- Merge algebra (`lib/rule_helpers.ex:52-89`): three layers folded, later wins —
  built-in defaults → `config :credence, :assumptions` → call `opts[:assumptions]`. A layer may
  be a **map** (patches only named keys, `:80`), **`:strict`** (all keys off, `:75-76`), or
  **`:default`** (reset to defaults, `:78`). Unknown values raise (`:85-89`); user layers
  validated (`:82-83`).
- Filtering: `filter_by_assumptions/3` (`:111-124`) keeps a rule iff `missing_assumptions`
  (a rule's needed switches not currently on, `:97-99`) is empty. **Filtering runs even when the
  caller passes an explicit `rules:` list** (`lib/pattern.ex:154-162`) — naming a rule can't
  punch through the safety guarantee. Filtered rules log a warning; an *unknown* switch is
  treated as never-satisfiable and always warns (`:132-148`).
- Only **6 Pattern rules declare assumptions** (grep): 3 use `[:single_codepoint_graphemes]`
  (`avoid_graphemes_enum_count_with_predicate`, `no_codepoint_string_reverse`,
  `prefer_graphemes_for_character_uniqueness`), 1 uses `[:proper_lists]` (`redundant_list_guard`),
  and `no_piped_regex_replace` declares `[]`. So the switch system currently gates a tiny slice
  of rules.

### 2.5 `unsafe_in_dsl()` mechanism

- 13 Pattern rules declare it (grep). Values observed: `:all` (×5), `[:ash_expr]` (×2),
  `[:ash_expr, :ecto_query]` (×1), `[:ash_expr, :nx_defn]` (×1), `[:nx_defn]` (×3). Rules
  include `no_cond_two_clauses`, `no_if_true_false`, `no_tautological_if`, `no_manual_max`,
  `no_manual_min`, `prefer_erlang_float`, `prefer_function_capture`, `prefer_negate_if_true_false`,
  etc. Consumed only by the DSL gate (§1.8); default `[]` means "safe everywhere".

### 2.6 `Issue` struct (`lib/issue.ex`)

`defstruct [:rule, :message, meta: %{}]` (`:5`); type `%{rule: atom, message: String.t, meta: map}`
(`:7-11`). `meta[:line]` is the load-bearing field — used for DSL suppression (`lib/pattern.ex:39`),
corpus finding identity (`lib/credence/corpus/findings.ex:80-83`), and drift reporting. There is
**no column, no rule-module, no patch/provenance field** on the struct (see §6.4).

---

## 3. QA MACHINERY

### 3.1 Per-rule test harness (`test/support/rule_case.ex`)

`use Credence.RuleCase` is the one template for every per-rule test (`:44-55`). Verbs:
`check/2`, `flagged?/2`, `clean?/2` (`:62-71`), `fix/3` = `RuleHelpers.apply_rule_fix`
(byte-exact production path, `:80-82`), `confirm_fix/2` (trailing-newline-insensitive equality,
`:95-97`), `valid_syntax?/1` (`:104`), `compiles?/1` (`:111-119`). Deliberately **byte-exact** —
no re-formatting before compare — so a rule that re-indents/reflows untouched lines fails
(`:29-41`).

Each rule has **three** test files: `_check_test.exs`, `_fix_test.exs`, `_equivalence_test.exs`.
Confirmed counts: **160 check + 160 fix + 160 equivalence** files under `test/pattern/`.

### 3.2 Meta-gates (`test/support/meta_test_support.ex` + the `*_meta_test.exs` files)

`MetaTestSupport` (`:1-19`) holds shared predicates so the generator pin and the real gates
assert the same contract. Test files are introspected with **Sourceror** (not
`Code.string_to_quoted`), so code inside heredoc fixtures is invisible to the walks (`:16-19`).
The six Pattern structural gates (enumerated in docs/08:90-100) plus new Syntax/Semantic gates:
- `rule_test_completeness_test.exs` — triplet files exist + correctly-named modules.
- `check_meta_test.exs` — check test has a positive (`flagged?` or `check(...) != []`) and a
  negative (`clean?` or `check(...) == []`) (`has_positive?`/`has_negative?` `:119-135`).
- `fix_meta_test.exs` — fix test asserts a real transform, whole-string `==` / `confirm_fix`,
  bans partial matchers (`=~`, `String.contains?`, AST-normalizing round-trips)
  (`partial_match?`/`transform?` `:146-176`).
- `equivalence_meta_test.exs` — each rule has its own `*_equivalence_test.exs` calling a real
  `assert_equivalent*` or an explicit `mark_equivalence_*`, references the rule, no
  `:equivalence_todo` skeleton (`assert_fns`/`mark_fns` `:189-194`).
- `no_parser_calls_in_rule_tests_test.exs` — no bare `Code`/`Sourceror` refs in test files
  (`parser_ref?` `:183-184`).
- `fixture_string_escaping_test.exs` — fixtures must be in canonical string form
  (`fixtures/1`, `fixture_ok?/1` `:313-395`).
- `syntax_meta_test.exs` / `semantic_meta_test.exs` — union/prefix gates tolerating multi-file
  fix suites, adding fix-output-validity (`valid_syntax?(fix(...))`) checks (docs/08 §3b).

### 3.3 Corpus (`lib/credence/corpus.ex`, `test/corpus/`)

- The corpus is **~500 entries**: `@packages` = ~465 pinned hex libraries
  (`lib/credence/corpus.ex:28-529`) + `@repos` = ~37 large application repos (Supabase
  supavisor/realtime, Livebook, Plausible, Blockscout, Elixir itself, Ash ecosystem, …) shallow-
  cloned at exact SHAs (`:537-606`). Fetched idempotently into a gitignored `corpus/` dir via
  `mix hex.package fetch` / `git fetch --depth 1 <sha>` (`ensure_fetched!` `:664-667`,
  `fetch_repo!` `:672-692`). `lib_files/1` globs `**/lib/**/*.ex` excluding
  `deps/_build/test/node_modules/.git` (`:644-652`).
- **Premise:** this is well-reviewed production code, so Credence should find nothing; any
  finding is a candidate over-fire unless reviewed-legit (moduledoc `:5-19`).
- **What the test asserts is NOT zero findings — it is a per-finding snapshot ratchet.**
  `Credence.Corpus.Findings` formats every Pattern finding to a stable identity
  `"<path>:<line>  <rule>"` with an `(xN)` suffix for exact duplicates
  (`lib/credence/corpus/findings.ex:77-86`). `over_firing_test.exs` runs `Pattern.analyze`
  per package (parse-only, `:86-103`) and asserts `actual == expected` where `expected` is the
  package's lines from `test/corpus/accepted_findings.txt` (`:94-101`). A **NEW** line ⇒ candidate
  over-fire (red, with a self-contained explanation — rule complaint + source excerpt +
  line-numbered diff of that rule's fix + before/after Sourceror AST, `:105-334`); a **GONE** line
  ⇒ rule narrowed/removed (red, re-pin). Re-pin with `mix credence.corpus --update-snapshot`.
- **The snapshot is a whitelist of accepted findings, and it is large: 6137 accepted findings**
  (`test/corpus/accepted_findings.txt`, non-comment lines). Top accepted rules:
  `prefer_heredoc_for_multi_line_doc` (1298), `prefer_map_new` (503), `no_case_true_false` (475),
  `prefer_function_capture` (334), `prefer_guard_over_if` (227). So the "premise" is aspirational —
  in practice thousands of findings are pinned as reviewed-legit suggestions, not over-fires.
- **`fix_safety_test.exs`** (`test/corpus/fix_safety_test.exs`) closes the analyze-only gap:
  it *applies* each accepted finding's single-rule fix to real corpus source and asserts three
  metamorphic invariants — **no dropped comment** (`lost_comments` via
  `string_to_quoted_with_comments`, `:263-278`), **no introduced `__`-mangled variable**
  (`introduced_mangled_vars` `:198-234`), **no over-reach** (a re-wrapped/reformatted hunk with
  no real token change, `rewrap_hunks`/`regions`/`over_reach_in_region` `:116-171`). One test per
  entry, all three checks share one fix computation (`:55-93`).
- Other corpus layers: `over_firing_test.exs` (analyze snapshot), `scope_parity_test.exs`,
  `fix_breakage_test.exs`, `findings_test.exs`. `Credence.Corpus.FixBreakage`
  (`test/support/fix_breakage.ex`) adds dependency-free structural detectors for fixes that
  parse but wouldn't compile / silently change behaviour: `:mangled_attr`, `:bad_arity` (arity
  after pipe-expansion), `:unsubstituted_equality_guard`, `:bad_defguard`,
  `:deleted_dynamic_clause` (`:1-42`, detectors `:90-266`).

### 3.4 Behaviour-equivalence harness (docs/07) — implemented in `test/`, not maintainer_tools

`Credence.BehaviourEquivalence` (`test/support/behaviour_equivalence.ex`) is **plain `mix test`
machinery, a third per-rule test kind, no separate runner** (moduledoc `:12-13`). Three tiers:
- `assert_equivalent/2` — **T1 expression**: wrap before/after in `fn <vars> -> expr end`, apply
  per input (`:69-94`).
- `assert_equivalent_module/2` — **T2 module-call**: compile whole before/after modules under
  unique names, invoke a function over inputs (`:110-133`, `compile_module!` `:312-318`).
- `assert_effect_trace_equivalent/2` — **PROBE**: supply a recording `effect` fn, assert call
  order+count identical (`:151-181`, `run_with_trace` `:320-330`).
- Opt-outs (reason mandatory): `mark_equivalence_cosmetic/1`, `mark_equivalence_unconstructible/1`,
  `mark_equivalence_repair/1` (`:186-214`).

Comparison is **strict `===`** to catch int↔float value-kind changes (`:88`), with exception
parity via `eval_outcome/2` tagging `{:ok,v}|{:raise,mod}|{:throw,t}|{:exit,t}` (`:223-244`).
Anti-stub checks live in `precheck!`/`check_discrimination!` (`:248-298`): rule must fire, a
rewrite must have happened, ≥3 inputs, and inputs must **discriminate** (original produces ≥2
distinct outcomes). `test/behaviour_equivalence_self_test.exs` proves each safety check refuses
a broken setup; `test/equivalence_regression_test.exs` rebuilds 8 rejected rewrites and proves
the harness would catch each divergence. Curated inputs in `test/support/equivalence_inputs.ex`.
There is also a **classify-time CLI** `mix credence.equiv` (`lib/mix/tasks/credence.equiv.ex`)
that reuses `BehaviourEquivalence` + `EquivalenceInputs` to emit an EQUIVALENT | REPAIR | DIVERGES
verdict — must run under `MIX_ENV=test` (`:1-30`).

### 3.5 Self-heal fixtures (docs/10) — `test/support/fixture_healer.ex`

`Credence.FixtureHealer.heal_dirs/0` runs in `test/test_helper.exs:31` **before the suite
compiles**, deterministically rewriting fixtures + fix-assertions into one canonical form.
Two passes (`heal_file/1` `:59-78`): (1) `assert fix(...) == expected` → `confirm_fix(fix(...),
expected)` (incl. `result = fix(...)`; `assert result == expected` var-bound shape) and ensures a
scoped `import Credence.RuleCase, only: [confirm_fix: 2]` (`:120-206`); (2) canonicalize fixture
string forms — internal newline → heredoc, single-line no-`"` → plain, single-line with `"` →
`~S'…'` (`:214-250`). **Write-safety is load-bearing:** a file is written only if the result
parses, doesn't increase the flagged count, and preserves every fixture value up to trailing
newlines (`convert_safe?`/`values_kept?` `:258-300`); `heal_file` is `rescue`-guarded to never
brick the suite (`:76-77`). Idempotent — a no-op once canonical.

### 3.6 Representative rule tests (3 examples)

- `test/pattern/no_sort_then_at_equivalence_test.exs` — T1 equivalence; two `assert_equivalent`
  calls with `vars: [:nums]`, `inputs: B.term_lists()` (leads with `[]`); moduledoc documents the
  empty-collection regression (bare `Enum.min/1` raised vs `nil`, now `empty_fallback` form).
- `test/credence_pipeline_test.exs` — end-to-end invariants: "fix must not break compiling code"
  (`:708-714`), idempotency (`:717-737`, single small example — see §6.1), revert behaviour
  (`:343`, `:425`, `:441`, `:460-480` — `{BrokenFixRule, :reverted}` and "a reverted rule does not
  poison the rest of the pipeline").
- `test/pattern/no_sort_then_at.ex` is the rule; its check does a `Macro.prewalk` collecting
  issues (`lib/pattern/no_sort_then_at.ex:41-74`), `fix_patches` uses `patches_from_postwalk`
  (`:77-95`) — the standard shape.

---

## 4. MAINTAINER TOOLS (`maintainer_tools/`)

All four are **autonomous, sandboxed Claude loops**; a wrapper shell script owns all git and all
list edits, the LLM session's only output channel is a `_verdict` file. Shared spirit: one fresh
session per unit, self-heal + retry-with-backoff on transient failures.

- **`stage_1_promote_fixable_rules/`** (`README.md`) — drives review of *fixable* candidate rules
  from `candidates.md` (generated from the `evolution` sister branch), one session per rule set
  (rule file + tests). The bar: "exact same answer for every admitted input." Session is
  no-git, edits only the set's files, writes `_verdict` = `ACCEPT` or `FOLLOWUP: <reason>`. The
  wrapper independently re-verifies before committing: rule exists and isn't a check-only stub,
  test shape matches the kind (pattern = split `_check`/`_fix` + real non-`[]` `fix_patches`),
  diff confined to the set, whole `mix test` green. Scripts: `generate_candidates.sh`,
  `review_loop.sh`, `review_lib.sh`, `copy_next_candidate.sh`, `move_unfixable_out.sh`,
  `remove_from_list_{keep,revert}_files.sh`, `changelog_guard.sh` (CI guard: a safety-switch
  default change needs a matching CHANGELOG entry).
- **`stage_2_promote_non_fixable/`** (`README.md`) — near-identical copy of stage 1, standalone
  (no cross-stage sourcing). Drains the **check-only stubs** in `unfixable_unreviewed.md` (rules
  whose `fix_patches/2` is the dead `[]` form that stage 1 auto-classified unfixable and never
  reviewed). Tries to author a safe fix for all-or-a-narrower-subset of what `check/2` flags. A
  **three-way verdict**: `ACCEPT` (rule joins tree), `UNFIXABLE: <reason>` (→ `unfixable_confirmed.md`),
  `FOLLOWUP: <reason>` (→ `followup.md`). Gate failures/unrecognized verdicts default to
  followup, never to confirmed. Precondition: stage 1 done (`candidates.md` empty).
- **`stage_3_resurrect_followups/`** (`README.md`) — share-nothing re-examination of rules in
  `followup.md` (~40 rejected). Decides whether a rejection can now be overcome: split a
  single-file testsuite, narrow to a fixable core, reuse an existing switch, or **propose** a new
  assumption. New switches are **propose-only** — the session NEVER edits `lib/assumptions.ex` /
  `CHANGELOG.md` (the confined-diff gate enforces this); it writes to `proposed_assumptions.md` +
  `proposed_rules_requiring_assumptions.md`. Drains `followup.md` directly (a "row" is one `##
  <base>` section). 5-way verdict: `ACCEPT` / `PROPOSE_SWITCH_NEW` / `PROPOSE_SWITCH_REUSE` /
  `UNFIXABLE` (→ `stage3_unfixable.md`) / `KEEP` (stays in followup.md). ACCEPT gate additionally
  requires a `*_property_test.exs` for any rule declaring `assumptions/0`. Precondition: stages 1
  AND 2 done.
- **`corpus_whitelist_validator/`** (`README.md`) — autonomously re-audits
  `test/corpus/accepted_findings.txt` in 100-finding batches, one **read-only, no-git** session
  per batch (no Edit/Write/git tools). Re-checks each accepted finding for over-firing and unsafe
  auto-fixes, capturing the session's final message as `reports/batch_NNN.md`. It never touches
  the whitelist or rules — acting on flags is a human decision. Helper `showfix.exs` shows a
  rule's real fix diff on a corpus file. Resumable (a batch with a non-empty report is skipped).
  Contains its own 526KB `accepted_findings.txt` copy + a large `FIX_LOG.md`.

Data files at `maintainer_tools/` root: `candidates.md` (empty now), `followup.md`,
`unfixable_confirmed.md` (23KB — the durable proven-unfixable queue).

---

## 5. DOCS (`docs/01`–`docs/11`) — summaries

- **01 `01_ast-callback-interface-analysis.md`** — historical look-back at how Pattern rules got
  the `fix_patches/2` shape. Original rules each had `fix(source,opts) :: String.t()` that parsed,
  walked, re-stringified the *whole* tree, causing layout loss and no non-interference guarantee,
  plus a warn-only mode nobody could act on. The move to `fix_patches/2` + `apply_or_revert` +
  parking 15 unfixable rules made "fix it or don't exist" a structural property. **Note: this doc
  is stale** — it still lists a `fix/2` callback and `fixable?/0`, both since removed; the counts
  (76 rules) predate today's 160.
- **02 `02_rule-review-process.md`** — the human step-by-step for accepting AI-written rules from
  `evolution`. States the one bar ("exact same answer for every admitted input; `:strict` = every
  possible input"), the one-set-at-a-time discipline, the correctness-check recipe (Unicode/edge/
  value-kind/aliased-variable/side-effect nasty inputs), the decision table (keep / narrow / gate
  behind a switch / re-aim / delete), the split `_check`/`_fix` test layout, and the "used
  somewhere else" variable-capture trap. Correctness decisions must be written into `CONTEXT.md`
  + `prompt.md`.
- **03 `03-safety-switches.md`** — the design of `Credence.Assumptions` (0.7.0). A switch is the
  *weakest checkable promise about running data* (not source) that makes a rewrite safe; `:strict`
  = no promises (bit-identical), the default = a small curated set on. Reframed invariant:
  "Credence never changes behaviour on any input your stated promises admit." Rules AND their
  promises; a rule needing a promise for one shape but not another must be **split**; a
  property test is required to gate a rule behind a switch; a *type* change can't be promised
  away. Flat, shared switch list; three-layer merge (call > config > defaults).
- **04 `04-autonomous-review-loop.md`** — the stage-1 loop design: sandboxed no-git LLM session
  per candidate set, wrapper owns git + list edits + the re-verify gate, `_verdict` = ACCEPT |
  FOLLOWUP. Details set-grouping (longest-rule-base-prefix-wins), greenfield-vs-delta
  classification via `git status`/`git diff`, per-kind gates, self-heal, orphan-test routing, and
  the deterministic `unfixable_stub?` pre-pass (pattern = single-clause `fix_patches -> []`).
- **05 `05-maintainer-tools-reorg-and-stage2.md`** — reorganizing `scripts/` + list files into
  `maintainer_tools/stage_N/` subdirs, and building stage 2 as a full standalone copy of stage 1
  with a flat-list queue (`unfixable_unreviewed.md`), a stub-focused prompt, and the three-way
  verdict. `UNFIXABLE:` means "no safe fix for any shape"; duplicates/shared-file-needs →
  followup; `unfixable_confirmed.md` is the durable human-review queue.
- **06 `06-stage3-resurrect-followups.md`** — stage 3 design: re-examine `followup.md` rejects,
  drain the file directly (whole-section deletes), propose-only new switches (two dedup'd catalog
  files), 5-way verdict, KEEP leaves the section in place. Briefing injects the original rejection
  reason + full `lib/assumptions.ex` + the pending catalog so the session knows what a narrowing/
  switch must overcome.
- **07 `07-behaviour-equivalence-harness.md`** — the equivalence-suite plan (§3.4). Notably it is
  a *log of the backfill*: it classifies rules into T1/T2/T3a/T3b/T3c/PROBE, records the
  divergences found (shipped-rule bugs) and their resolutions (narrow/gate/fix/merge/drop/repair),
  and marks **BACKFILL COMPLETE — 0 skeletons, 0 excluded, every rule has a real equivalence
  test** (`:441-443`), rule count 125→117 at that time (since grown to 160). The gate
  (`equivalence_meta_test.exs`) is live and hard-flipped.
- **08 `08-rule-scaffolding-generator.md`** — `mix credence.gen.rule <Name> [--type ...]`
  (`lib/mix/tasks/credence.gen.rule.ex`) + `Credence.RuleScaffold` + `Credence.RuleName` as the
  single name/path source of truth, plus a generator "pin" (`generator_meta_test.exs`) asserting
  scaffold output passes the same structural predicates the real gates use. Unifies the six
  Pattern gates' predicates into `MetaTestSupport` and adds Syntax/Semantic completeness+substance
  gates (fix-output-validity via `valid_syntax?`). Generated tests are honest-red until filled.
- **09 `09-corpus-over-firing-tests.md`** — the corpus layer (§3.3). Also a triage log: the first
  corpus run surfaced 1760 findings across 50 firing rules → 13 confirmed over-fire *bugs* (12
  high-sev, where a fix deletes/alters correct code that still compiles). Records the fix pass
  (crash fix, 6 clause-analysis bug fixes, ~10 rules dropped/narrowed) and the shift from a
  rule-level allowlist to the per-finding `file:line` snapshot ratchet. Many rules named here no
  longer exist (`avoid_rebinding_parameter`, `no_kernel_shadowing`, `prefer_private_helpers`, …
  all dropped).
- **10 `10-self-heal-fixture-heredocs.md`** — the fixture convention (one canonical form per
  value) + `confirm_fix/2` + the `FixtureHealer` self-heal passes (§3.5), with the verify-before-
  write safety principle.
- **11 `11-qa-roadmap.md`** — QA roadmap grounded in refactoring-engine research (translation
  validation, `DoesNotCompile` oracle, mutation testing, differential precondition checking,
  bounded-exhaustive generation). Maps each research concept to what Credence has vs the gap.

### 5.1 Roadmap items (docs/11) — done vs not done, from the code observed

| Roadmap item (docs/11 §) | Status | Evidence |
|---|---|---|
| Translation-validation spine (fire-safe-core, else no-action) | **DONE (core design)** | `apply_or_revert` `lib/pattern.ex:129-148`; `apply_rule_fix` self-revert `lib/rule_helpers.ex:279`; `:strict` |
| §2 `DoesNotCompile` / compile-the-fixed-corpus oracle | **PARTLY DONE** | `fix_safety_test.exs` applies fixes + checks comment/mangle/over-reach; `FixBreakage` structural compile-proxy detectors. But it is metamorphic/structural, **not an actual `Code.compile` of the fixed corpus** (corpus files can't compile standalone — `fix_breakage.ex:6-12`). The generic compile oracle §2 asks for is **not** implemented. |
| §1 property-based differential oracle (StreamData into the equivalence harness) | **NOT DONE** | `behaviour_equivalence.ex` uses **curated fixed inputs** (`EquivalenceInputs`); docs/07 explicitly leaves StreamData "additive, future" (`07:461`); `stream_data` is a test dep (`mix.exs:40`) but not wired into equivalence |
| Behaviour-equivalence suite over every rule (the doc's own §1 prerequisite) | **DONE** | 160 `*_equivalence_test.exs`; `equivalence_meta_test.exs` hard gate; `test_helper.exs:11-15` |
| §3 mutation-testing the rules | **NOT DONE** | no `muzak`/`mutate` dep in `mix.exs`; no mutation harness found |
| §4 shared differential-precondition / scope-binding library | **NOT DONE** | rules hand-roll their safe cores (docs explicitly keep rules self-contained); no shared read/write-var helper in `rule_helpers.ex` |
| §5 bounded-exhaustive small-program generation (JDolly analog) | **NOT DONE** | no generator found |
| §6/Q4 canonical AST normal form | **PARTIAL/AD-HOC** | `mix format` + `strip_layout_meta`/`strip_all_meta` used ad hoc (`rule_helpers.ex:725-730`,`879-896`); no single reusable normal form |
| §7 Q1 Elixir/BEAM equivalence checker | **NOT DONE** (open research) | — |
| §7 Q2 static source-safety checker | **NOT DONE** (open research) | — |

Net: the *static safe-core spine* and the *per-rule equivalence backfill* are done; the
*property-based*, *mutation-testing*, *shared-precondition*, *bounded-exhaustive*, and *true
compile-oracle* items are open.

---

## 6. WEAKNESSES (pipeline-level)

### 6.1 Single-pass Pattern round → ordering & idempotency hazards
The Pattern round is one forward `Enum.reduce` in `{priority, module}` order
(`lib/pattern.ex:80`), not a fixpoint. Consequences:
- **A rule's fix can create work for an earlier-ordered rule that never runs again in this
  call.** Because 153/160 rules share priority 500 and are ordered *alphabetically by module
  name* (§2.3), the ordering is essentially arbitrary w.r.t. fix dependencies. There is no way
  to express "run B after A" except by hand-tuning one of the 6 numeric priorities.
- **`fix` is therefore not guaranteed idempotent in general.** A second `Credence.fix` pass
  would pick up any work an earlier-ordered rule missed. The idempotency invariant is asserted by
  exactly **one** test with **one** tiny fixture (`test/credence_pipeline_test.exs:717-737`), which
  cannot exercise cross-rule ordering interactions. `Credence.fix` itself does not re-run the
  Pattern round to convergence, and the final `analyze` only *reports* remaining issues — it does
  not fix them (`lib/credence.ex:56`). So a caller can receive `%{code, issues: [...]}` where
  `issues` are real, fixable-on-a-second-call findings.

### 6.2 Performance: parse-per-rule, check ×2, compile-per-firing-rule
Per `fix` call (§1.5): **160 `Sourceror.parse_string` re-parses** and **160 `check` prewalks** in
the reduce, plus another 160 checks + 160 `dsl_dropped_ranges` in the final `analyze` — check
runs ~320×. The source is re-parsed on **every**
iteration even when unchanged (no caching between two non-firing rules). Each firing rule triggers
a full `Code.compile_string` in `apply_or_revert` (`lib/pattern.ex:135`) on top of the round's gate
compile (`:69`) and the final semantic analyze compile. `Code.compile_string` is the dominant cost
and it **executes module-body code** (§6.3). `discover_rules` is also re-run (not memoized) on every
`rules()`/`default_rules()` call (`lib/rule_helpers.ex:20-24`, called from `analyze` and
`fix_with_trace`).

### 6.3 Compilation is contained, but compile-time effects remain relevant
`compiles?`/`compile_and_capture` run `Code.compile_string` in a monitored child with a default
64-million-word heap ceiling and 30-second deadline. A heap breach, timeout, or child exit becomes
an error diagnostic instead of taking down or indefinitely blocking the caller. The child also
tracks and terminates processes spawned by the compiled source. Compilation still evaluates
module-level code, so external side effects performed before termination cannot be rolled back;
the containment guarantee is bounded execution, not transactional isolation.

### 6.4 No patch-level provenance to the caller
`Credence.fix` returns `applied_rules :: [{module, count | :reverted}]` (`lib/credence.ex:40-44`)
— *which* rules fired and how many issues each had, but **not which bytes/lines each rule
changed**. Per-rule before/after diffs exist only as `Logger.debug` side effects
(`lib/rule_helpers.ex:909-920`, `lib/pattern.ex:140`,`:145`). A caller cannot obtain patch-level
provenance (which rule touched which line) programmatically. The `Issue` struct also carries no
column and no rule module (`lib/issue.ex:5`), only `rule` atom + `meta[:line]`.

### 6.5 Safety remains asymmetric across the three rounds
The **Pattern** round compiles and reverts each changed rule. The **Semantic** round re-measures
every changed pass, attributes parse/compile regressions or strictly-added unrepaired errors,
reverts culpable fixes, and records them as `:reverted`; ambiguous unsafe replay reverts the whole
pass. The **Syntax** round still applies each text fix and only logs whether the result parses at
the end, without reverting. Thus Pattern and Semantic now have different repair-safety gates,
while Syntax remains the unguarded phase.

### 6.6 analyze/fix desync on the parse/comment self-revert path
The DSL gate keeps `analyze` and `fix` in lockstep (§1.8): a finding is suppressed iff its fix is
dropped. But the **other** self-revert inside `apply_rule_fix` — output doesn't parse OR comment
multiset changed (`lib/rule_helpers.ex:279`) — has **no analyze-side counterpart**. When it fires,
`apply_rule_fix` returns the original source, `apply_or_revert` sees `fixed == source` → "no change"
(`lib/pattern.ex:131-133`), and the final `analyze` still reports the finding. Result: a finding
that is **reported but silently not fixed** — the one documented exception to "every Pattern rule
fixes what it finds," and unlike the DSL case it is invisible (no `:reverted` marker, no
suppression).

### 6.7 No crash isolation around `rule.check` / `rule.fix_patches`
`reject_dsl_unfixable` (`lib/pattern.ex:34-41`) and `run_fixable_rules` (`:86`) call `rule.check`
with **no try/rescue**; only `dsl_dropped_ranges` wraps `fix_patches` (`lib/rule_helpers.ex:316-320`).
A single buggy rule that raises on some AST crashes the entire `Credence.analyze`/`fix` call.
docs/09 records exactly this happening in production (`prefer_remove_unused_private_fn_param`
raising `:erlang.length(nil)` on 36 corpus files). There is no per-rule fault boundary.

### 6.8 The corpus "zero findings" premise is really a 6137-line whitelist
`over_firing_test.exs` asserts equality to a pinned snapshot, not zero
(`test/corpus/over_firing_test.exs:101`). The snapshot has **6137 accepted findings**
(`test/corpus/accepted_findings.txt`). Two consequences: (a) the guard is a *drift ratchet*, so a
rule that starts over-firing on genuinely-broken *new* code inside an already-accepted pattern is
only caught because the key is `file:line` (a coarser key would miss it — the doc acknowledges this
tradeoff, `findings.ex:18-24`); (b) bumping any package version shifts line numbers and forces a
full re-pin (intended but heavy). One finding pins with a `:?` line placeholder because
`prefer_map_new_with_transform` emits no line meta (`docs/09:476`) — a rule gap normalized into the
snapshot.

### 6.9 Most rules still use the alphabetical tiebreak
The priority mechanism is documented in `docs/20-rule-ordering-policy.md`: a non-default priority
must state the ordering assertion it makes, contended Semantic diagnostics must be decided by a
declared priority, and independent rules should remain at 500. Currently 18 rules declare an
override (7 Pattern, 11 Semantic, no Syntax); 153/160 Pattern and all 46 discovered Syntax rules
therefore still use the alphabetical tiebreak. That is expected for independent rules but remains
a hazard if an interaction is not identified and declared under the policy.

### 6.10 Logging is debug-only and side-channel
All fix tracing is `Logger.debug` with a `[credence_fix]` prefix (`lib/pattern.ex:67`,
`lib/rule_helpers.ex:919`); broken-fix reverts log at `warning` (`lib/pattern.ex:136`). A library
consumer running at `:info` sees nothing about what happened inside a fix beyond the coarse
`applied_rules` tuples. There is no structured event stream, no callback, no telemetry.

### 6.11 Config surface is minimal and undocumented centrally
Four config knobs exist: `config :credence, :assumptions`, `:dsl_macros`,
`:compile_max_heap_words`, and `:compile_timeout_ms`. `max_passes` remains opts-only for the
Semantic round, with no config fallback. There is still no config for logging, disabling rounds,
or phase-specific timeouts; the compile timeout and heap ceiling cover every compilation through
`compile_and_capture/2`.

### 6.12 `Code.string_to_quoted` used in `lib/` despite the "Sourceror-only" policy
The project's stated parsing policy is Sourceror-only (docs/08:78-82 claims the sole
`Code.string_to_quoted` user is one test line). But `lib/rule_helpers.ex` uses
`Code.string_to_quoted` in `parses?` (`:354-357`) and `Code.string_to_quoted_with_comments` in
`comment_multiset` (`:365-377`), and `Code.compile_string` throughout. These are the parse/comment
self-revert guards on the hot path — a policy inconsistency (minor, but it means two parsers judge
"does this parse": Sourceror for the AST, `Code` for the guard).

### 6.13 DSL guard is a best-effort denylist with a known blind spot
`DslGuard` cannot see through wrappers that hide an import (`use MyAppWeb, :resource`) except via
`config :credence, dsl_macros:` (moduledoc `:67-76`, `:105`). Its Ash `filter`/`calculate`/
`aggregate` path depends on a same-file `Ash.*` import (`:500-516`), which the wrapper case
defeats. An AST-reinterpreting DSL that is neither built-in nor configured is unprotected. This is
an accepted-risk denylist, not a guarantee — a wrong fix inside an unrecognized DSL still compiles
and fails only at runtime.
