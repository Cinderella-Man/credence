# Rule scaffolding generator + contract pin

## Context

Writing a new Credence rule means re-discovering an unwritten contract by tripping the
structural meta tests one failure at a time (triplet naming, positive+negative check cases,
whole-string `==` fix, heredoc-only fixtures, no direct parser calls, equivalence shape).
The contract is *enforced* well but never *stated* in one place — candidate 1 from the
architecture review (a locality problem: "what a valid rule-test looks like" is shallow-spread
across many files).

Fix: a deterministic generator that **embodies** the contract as a template, emitting a
correctly-shaped rule + its test files for any type. The AI/human then fills the blanks.
A pin meta test runs the generator and asserts its output passes the same structural
predicates the real meta tests use — so the generator becomes the executable
single-source-of-truth and cannot drift from the gates silently.

This work also **closes the Syntax/Semantic gate gap**: today only Pattern rules have
substance gates; Syntax/Semantic rules can ship inert and untested. We add union-based
completeness + substance gates for both types (see §3b) so a Syntax/Semantic rule can no
longer silently do nothing.

Decisions locked with the user:
- **All three types** (Pattern / Syntax / Semantic) get a scaffold + the pin.
- **Pin it** — a meta test gates the generator output against the contract.
- **Honest red** — stubs fail their own assertions until filled; they do NOT fake-green.
- **Ships in `lib/`** — the generator lives in `lib/` (needed at `:dev` for the Mix task)
  and ships in the hex package, idiomatic like Phoenix/Ecto generators.
- **Format output** — the Mix task runs `mix format` on the files it writes.
- **Abort on collision** — if any target file exists, write nothing (no `--force` for now).
- **One name/path source of truth (Option A)** — a single helper turns a short name into
  snake / Pascal / rule module / test module / test path; the generator, the pin, *and* the
  real gates all call it. No more hand-typed path formulas.
- **Full predicate unification across all six Pattern structural gates** — lift the predicates
  into `MetaTestSupport` so the pin and the real meta tests call the same code.
- **Equivalence stub is always `assert_equivalent`** with **literal `inputs:` + a TODO**
  pointing at `Credence.EquivalenceInputs`. Opt-out (`mark_equivalence_*`) is a by-hand swap
  for the rare cosmetic/repair rule.
- **New Syntax/Semantic gates: Tier 2 + the syntax fixpoint line** (`analyze(fix(x)) == []`).
  Fix-output-validity (`valid_syntax?(fix(x))`) **shipped as a follow-up** for both
  rounds — see §3b. (`compiles?` was evaluated and rejected: it is false for correct
  fixes whose fixtures are bare `def`/expression fragments or need a running ExUnit
  context, so `valid_syntax?` is used uniformly — no allowlist.)
- **Gates are union/prefix-based (Option A)** — they accept multi-file fix suites (e.g.
  `undefined_function`'s six strategy files) and single combined files, not just the canonical
  2-file split. The generator still emits the clean 2-file split for new rules.
- **Retrofit existing Syntax/Semantic tests in-work (i)** so the suite stays green. **When a
  rule can't comply without a behavior change (decision b): stop and report it** — do not fix
  the rule's behavior silently and do not carve an exemption allowlist.

## Claims verified against the code

- No `--warnings-as-errors`, no format-check test, no hard-coded rule count → a new inert
  rule + unformatted-template risk won't break unrelated tests (`mix.exs:1`, `test_helper.exs`).
  `rule_status_test.exs:18` (`length(rule_status()) == length(default_rules())`) is
  **self-balancing** — both sides derive from `discover_rules/1`, so an inert rule keeps it green.
- Auto-registration via `@behaviour` (`RuleHelpers.discover_rules/1`, `lib/rule_helpers.ex:12`);
  no registry to edit. A stub Pattern rule (`check -> []`, `fix_patches -> []`) is **inert** —
  contributes no issues/patches, so pipeline/showcase/idempotency tests are unaffected.
- `assumptions_meta_test.exs` iterates `default_rules()` but is **satisfied trivially** by an
  inert stub: assumptions default to `[]`, so the "unknown switch" check is vacuous and the
  "switched rule needs a property test file" check is skipped. (The plan previously omitted
  this gate; it is safe but is now enumerated.)
- The equivalence precheck asserts `rule_fires?` **first** (`behaviour_equivalence.ex:240`),
  so an inert stub fails there with a clear "expected … to fire on:" message (honest red).
- The behaviour `__using__` macros inject `@behaviour` + default `priority/0` (Pattern also
  injects `assumptions/0` **and** `alias Credence.Issue`). **Syntax/Semantic `__using__` do NOT
  alias `Issue`** (`lib/syntax/rule.ex`, `lib/semantic/rule.ex`) — so the Syntax/Semantic rule
  templates must emit `alias Credence.Issue` themselves. Templates emit only `use Credence.<Type>.Rule`,
  never a bare `@behaviour`.
- **Correction to the prior draft:** the four Pattern meta tests do **not** all import
  `Credence.MetaTestSupport`. `check_meta`, `fix_meta`, `fixture_string_escaping`, and
  `no_parser_calls` import it; **`equivalence_meta_test.exs` does not** — it carries its *own*
  duplicate `walk_any?/2`, `calls_any?/2`, `bullets/2`, and a `Code.string_to_quoted`-based
  `load_ast/1` (`equivalence_meta_test.exs:68`). Lifting it therefore means deleting the
  duplicates and switching to the shared (Sourceror-based) helpers — slightly more than the
  other three, but still mechanical.
- `equivalence_meta_test.exs:68` is the **only** `Code.string_to_quoted` user in `lib/`+`test/`
  (verified by grep; the `Code.eval_string` hits in `behaviour_equivalence.ex` and
  `equivalence_regression_test.exs` *execute* code, outside the Sourceror-only **parsing**
  policy). So switching it to Sourceror cleanly makes CONTEXT.md's "appears nowhere" claim
  true (candidate 3, fixed for free).
- **Existing Syntax/Semantic tests do not follow one convention** (measured): of 7 syntax
  rules, 3 use a single combined `<snake>_test.exs` (`fix_div_rem`,
  `fix_python_augmented_assignment`, `fix_python_floor_div`); of 6 semantic rules,
  `unused_variable` uses a single file and `undefined_function` splits its fix tests **six
  ways by strategy** (no `undefined_function_fix_test.exs` exists). The new gates are therefore
  union/prefix-based, not strict-exact-name (see §3b).

## The six Pattern structural gates (and what unification covers)

| Gate file | Iterates | Enforces |
|---|---|---|
| `rule_test_completeness_test.exs` | `discover_rules(Pattern.Rule)` | triplet files exist + conventionally-named modules |
| `check_meta_test.exs` | `MetaTestSupport.rules()` | check test: asserts, references rule, positive + negative |
| `fix_meta_test.exs` | `MetaTestSupport.rules()` | fix test: asserts, references rule, whole-string `==`, real transform |
| `equivalence_meta_test.exs` | `discover_rules(Pattern.Rule)` | equivalence test: module + real assert/mark + references rule, no skeleton |
| `no_parser_calls_in_rule_tests_test.exs` | scans `test/{pattern,semantic,syntax}` | no `Code`/`Sourceror` refs in test files |
| `fixture_string_escaping_test.exs` | scans `test/{pattern,semantic,syntax}` | all fixtures are heredocs |

The pin (§4) covers paths/module-names (completeness), check/fix/equivalence substance, and
no-parser/heredoc fixtures. **All six** supply predicates the pin needs, so all six are
unified into `MetaTestSupport` and the pin delegates to the same code. (`assumptions_meta` is
not in scope: the generator emits `assumptions -> []`, which the gate accepts trivially.)

## Design

Split into a **pure scaffold** (returns file plans, testable without disk I/O) and a thin
**Mix task** (writes them). The pin reuses the pure scaffold.

### 0. `Credence.RuleName` — the single name/path source of truth (`lib/rule_name.ex`, new)

```elixir
@spec derive(name :: String.t(), type :: :pattern | :syntax | :semantic) :: %{
        snake: String.t(), pascal: String.t(), atom: atom(),
        rule_module: module(), rule_path: String.t()
      }
@spec test_module(derived, kind :: String.t()) :: module()   # e.g. NoFooCheckTest
@spec test_path(derived, kind :: String.t()) :: String.t()   # test/<type>/<snake>_<kind>_test.exs
```

- `name` accepted as `NoFooBar` or `no_foo_bar`; normalize via `Macro.underscore` / `Macro.camelize`.
- **`MetaTestSupport.test_path/2` and the inline path in `rule_test_completeness_test.exs:31`
  are deleted and re-expressed through `RuleName`** (they are byte-identical today, an existing
  duplication). The generator, the pin, and the gates now share one builder, so "cannot drift"
  is literally true for paths + module names, not just AST predicates.
- Lives in `lib/` (the Mix task needs it); pure, no I/O.

### 1. `Credence.RuleScaffold` — pure templates (`lib/rule_scaffold.ex`, new)

```elixir
@spec files(name :: String.t(), type :: :pattern | :syntax | :semantic)
        :: [{path :: String.t(), content :: String.t()}]
```

- Uses `RuleName.derive/2` for every path/module.
- Returns the rule file + its test files (no writes). Templates are plain strings (the project
  already builds code as strings; no AST printing). Fixtures are **real multi-line heredocs**
  (`"""\nfoo(bar)\n"""`), and use parseable placeholders (`foo(bar)` / `baz(qux)`) so
  `check/2`'s `Sourceror.parse_string!` never crashes on a fixture at runtime.
- **Out of scope:** assumptions/property-test scaffolding (assumptions default to `[]`).

**Pattern** → 4 files:
- `lib/pattern/<snake>.ex` — `use Credence.Pattern.Rule`; `@impl true def check(_ast,_opts), do: []`
  with a `# TODO` + `:<snake>`-atom Issue example in a comment; `@impl true def fix_patches(_ast,_opts), do: []`
  (TODO points at `RuleHelpers.patches_from_postwalk/2`). Moduledoc TODO with `## Bad`/`## Good`.
- `test/pattern/<snake>_check_test.exs` — module `Credence.Pattern.<Pascal>CheckTest`;
  `use Credence.RuleCase, async: true`; `alias` the rule; one `assert flagged?(Rule, heredoc)`
  (positive, **red** on inert stub) + one `assert clean?(Rule, heredoc)` (negative, green).
- `test/pattern/<snake>_fix_test.exs` — module `…FixTest`; `use Credence.RuleCase, async: true`;
  one `assert fix(Rule, input) == expected` with **different** input/expected heredocs (satisfies
  fix_meta `transform?`); stub `fix` returns input → **red**.
- `test/pattern/<snake>_equivalence_test.exs` — module `…EquivalenceTest`;
  `use Credence.RuleCase, async: true`;
  `assert_equivalent(heredoc, rule: Rule, vars: [:bar], inputs: [1, 2, 3])` with a
  `# TODO: replace with real inputs (see Credence.EquivalenceInputs, e.g. B.term_lists())`.
  Precheck "rule must fire" fails on the inert stub → **red**.

**Syntax** → 2 files:
- `lib/syntax/<snake>.ex` — `use Credence.Syntax.Rule`; **`alias Credence.Issue`**;
  `def analyze(_source), do: []`; `def fix(source), do: source`.
- `test/syntax/<snake>_analyze_test.exs` (`use ExUnit.Case`; `alias Credence.Issue` + the rule;
  local `defp analyze/1` wrapper) — positive `assert [%Issue{rule: :<snake>}] = analyze(heredoc)`
  (**red**) + negative `assert analyze(heredoc) == []` (green).
- `test/syntax/<snake>_fix_test.exs` (`use ExUnit.Case`; local `defp analyze/1`, `defp fix/1`) —
  transform `assert fix(input) == expected` (distinct heredocs, **red**) + fixpoint
  `assert analyze(fix(input)) == []` (green on stub). Matches `fix_python_modulo_*_test.exs` so
  fixture-escaping sees bare `analyze`/`fix`.

**Semantic** → 2 files:
- `lib/semantic/<snake>.ex` — `use Credence.Semantic.Rule`; **`alias Credence.Issue`**;
  `def match?(_), do: false`; `def to_issue(_), do: %Issue{rule: :<snake>, message: "TODO", meta: %{line: line(...)}}`;
  `def fix(source,_), do: source`; `defp line/1`.
- `test/semantic/<snake>_check_test.exs` (`use ExUnit.Case`; alias the rule) — positive
  `assert Rule.match?(diag)` (**red**) + negative `refute Rule.match?(other_diag)` (green) +
  attribution `assert Rule.to_issue(diag).rule == :<snake>` (green).
- `test/semantic/<snake>_fix_test.exs` (`use ExUnit.Case`; local `defp fix/2` wrapper) —
  transform `assert fix(input, diag) == expected` (distinct heredocs, **red**).

Honest-red holds for every type: each generated test file has ≥1 assertion that fails at
runtime on the inert stub (positive/transform), while the new required *shapes* (negative,
fixpoint, attribution) are present so the structural gates pass.

### 2. `Mix.Tasks.Credence.Gen.Rule` (`lib/mix/tasks/credence.gen.rule.ex`, new)

`mix credence.gen.rule <Name> [--type pattern|syntax|semantic]` (default `pattern`). Thin:
1. Normalize `<Name>` via `RuleName`; resolve type.
2. `RuleScaffold.files/2` → `[{path, content}]`.
3. **Abort** (print which path collided, write nothing) if any path already exists.
4. `File.write!/2` each; then `mix format` the written paths (`Mix.Task.run("format", paths)`).
5. Print created paths + a notice that the generated tests are **intentionally red** until
   filled. No registry edit needed (auto-discovery).

### 3a. Unify the six Pattern gates' predicates — `test/support/meta_test_support.ex`

Lift the predicates currently private to the six structural meta tests into
`Credence.MetaTestSupport` as pure `ast -> bool` (or `ast -> value`) functions; each gate
**delegates** (no assertion-behaviour change):
- `check_meta`: `has_positive?/1`, `has_negative?/1`, `check_call?`, `check_eq_empty?`.
- `fix_meta`: `partial_match?/1`, `transform?/1`, `fix_call?`, `fix_arg`, `@banned_matchers`.
- `fixture_string_escaping`: `fixtures/1`, `stringish?/1`, `ok?/1`, `multiline_interp?/1`, `@verbs`, `@fvars`.
- `equivalence_meta`: `defines_module?/2`, `@assert_fns`, `@mark_fns` — **and** drop its local
  `walk_any?/2`, `calls_any?/2`, `bullets/2`, switching its `load_ast/1` to the shared
  Sourceror-based `MetaTestSupport.load_ast/1` (drops `Code.string_to_quoted`, fixes candidate 3).
- `rule_test_completeness`: an AST-level `defines_module?(ast, module)` (the existing one reads
  a path; refactor to split path-load from the AST check so the pin can call it in-memory) +
  path/module derivation via `RuleName`.
- `no_parser_calls`: `parser_ref?/1`.

`MetaTestSupport` gains `syntax_rules/0`, `semantic_rules/0` (or a parametric `rules/1`) for §3b.

### 3b. NEW Syntax/Semantic gates (`test/syntax_meta_test.exs`, `test/semantic_meta_test.exs`, new)

Union/prefix-based, mirroring the Pattern gates but tolerant of multi-file fix suites and
single combined files. For each rule, the set of attributed test files is those under
`test/<type>/` whose name begins `<snake>_…_test.exs`, **anchored on suffix segments**
(`_analyze_test` / `_check_test` / `…_fix_test`) **and** that `references_rule?` the rule —
which removes any snake-prefix ambiguity. The required shapes must appear *somewhere in the
union*:

**Syntax** (`Credence.Syntax.<Pascal>`):
- *Completeness:* ≥1 analyze-side file and ≥1 fix-side file exist.
- *analyze substance:* a positive `analyze(...)` bound to `[%Issue{rule: :<snake>}]` (positive
  **and** attribution in one shape) + a negative `analyze(...) == []`.
- *fix substance:* a real transform (`fix(A) == B`, `A != B`, whole-string `==`).
- *fixpoint:* a line `analyze(fix(...)) == []` is present (Tier-3, kept — proven idiomatic at
  `fix_python_modulo_fix_test.exs:493`).
- *fix-output-validity:* a `valid_syntax?(fix(...))` assertion — the repaired source parses.

**Semantic** (`Credence.Semantic.<Pascal>`):
- *Completeness:* ≥1 check-side file and ≥1 fix-side file exist.
- *match? substance:* a positive `match?(...)` (asserted truthy) + a negative `refute match?(...)`.
- *attribution:* `to_issue(...).rule == :<snake>` is present.
- *fix substance:* a real transform (`fix(src, diag) == expected`, distinct).
- *fix-output-validity:* a `valid_syntax?(fix(...))` assertion — the repaired source parses.

**Fix-output-validity (failure mode #5) shipped** for both rounds via a
`valid_syntax?(fix(x))` gate. The tests `import Credence.RuleCase, only:
[valid_syntax?: 1]` (still `no_parser_calls`-safe — the verb hides the parser).
`compiles?` was evaluated and rejected: empirically false for correct fixes whose
fixtures are bare `def`/expression fragments (`UnusedVariable`, `UndefinedFunction`)
or need a running ExUnit context (`MissingUseExunitCase`), so a `compiles?` gate
would flag 3 correct rules. `valid_syntax?` is uniform and side-effect-free — no
allowlist, no decision-(b) reports.

All §3b predicates live in `MetaTestSupport` and are shared with the pin.

### 3c. Retrofit existing Syntax/Semantic tests (in-work, decision i + b)

Bring the 7 syntax + 6 semantic rules' existing tests into compliance with §3b so the suite
stays green when the gates land. Most already satisfy the shapes (the split-file rules do; the
single-file and multi-fix-file rules contain the shapes in their union). Where a test is merely
*missing a line* (a negative case, a fixpoint assertion, an attribution assertion), add it.
**Where a rule cannot comply without a behavior change** (e.g. its `fix` does not reach
`analyze(fix(x)) == []`, or it over-matches and has no clean negative input, or `to_issue`
emits the wrong atom): **stop and report that rule to the user with the specific failure** —
do not change rule behavior silently and do not add an exemption allowlist.

### 4. Pin meta test (`test/generator_meta_test.exs`, new)

For each type, call `RuleScaffold.files/2` with a sample name, parse each content with
Sourceror **in memory (no disk writes)**, and assert via the shared `MetaTestSupport`
predicates that the output would pass every gate:
- **Pattern:** correct paths + module names (via `RuleName`); check has positive+negative; fix
  has `transform?` + whole-string `==`; equivalence calls an assert and references the rule;
  all fixtures heredocs (`fixtures/1` + `ok?/1`); no `Code`/`Sourceror` refs (`parser_ref?/1`).
- **Syntax:** §3b syntax shapes (positive+attribution, negative, transform, fixpoint) + heredoc
  fixtures + no parser refs + correct paths/modules.
- **Semantic:** §3b semantic shapes (positive, negative, attribution, transform) + heredoc
  fixtures + no parser refs + correct paths/modules.

### 5. Docs (small, required)

- **README.md** — under `## Writing your own rules` (line 138), add a short lead-in: run
  `mix credence.gen.rule MyRule [--type ...]` to scaffold the rule + its tests (which start
  red); then fill in `check`/`fix`/fixtures.
- **CONTEXT.md** — `## Adding a Pattern rule — checklist` (lines 249-264): add a step 0 ("run
  `mix credence.gen.rule <Name>` to generate the rule + check/fix/equivalence skeletons —
  correctly named, heredoc fixtures, passing the structural meta gates; assertions start red,
  fill them in"). Refresh the now-stale step 4, which still says parse with
  `Sourceror.parse_string!/1` and call `apply_rule_fix/3` directly — replace with the RuleCase
  verbs (`check`/`flagged?`/`clean?`/`fix`). Add a short note that Syntax/Semantic rules now
  carry their own completeness + substance gates (§3b).
- **CHANGELOG.md** — one line under the current version (0.7.0, Unreleased).

## Files

- **New:** `lib/rule_name.ex`, `lib/rule_scaffold.ex`, `lib/mix/tasks/credence.gen.rule.ex`,
  `test/generator_meta_test.exs`, `test/syntax_meta_test.exs`, `test/semantic_meta_test.exs`.
- **Modified:** `test/support/meta_test_support.ex` (gains `RuleName` delegation + lifted
  predicates + per-type rule lists); the six Pattern meta tests `check_meta_test.exs`,
  `fix_meta_test.exs`, `fixture_string_escaping_test.exs`, `equivalence_meta_test.exs`
  (delegate; switch to Sourceror), `no_parser_calls_in_rule_tests_test.exs`,
  `rule_test_completeness_test.exs` (delegate path/module to `RuleName`); existing
  Syntax/Semantic test files brought into §3b compliance (§3c); `README.md`, `CONTEXT.md`,
  `CHANGELOG.md`.

## Reuse (don't re-implement)

- `RuleHelpers.discover_rules/1` (`lib/rule_helpers.ex:12`) — auto-discovery; no registry.
- `RuleHelpers.patches_from_postwalk/2` (`lib/rule_helpers.ex:390`) — referenced by the Pattern
  fix TODO.
- `MetaTestSupport` helpers already present: `walk_any?/2`, `count_nodes/2`, `calls_any?/2`,
  `references_rule?/2`, `src/1`, `equals_empty_list?/1`, `load_ast/1`, `short/1`, `bullets/2`
  (`test_path/2` is replaced by `RuleName`).
- `Credence.RuleCase` verbs (`flagged?`/`clean?`/`fix`/`check`) and `assert_equivalent`
  (imported via `use Credence.RuleCase`).
- Behaviour modules' `__using__` inject `@behaviour` + defaults — templates emit only `use`
  (Syntax/Semantic add `alias Credence.Issue` themselves).

## Verification

1. `mix credence.gen.rule NoExampleScaffold` → creates 4 pattern files, format-clean.
2. `mix test` → **only** the generated test files are red (pattern: check `flagged?`, fix
   transform, equivalence "rule must fire"); every meta gate is **green**. Confirms honest-red
   is localized and the structural contract is met.
3. Repeat for `--type syntax` and `--type semantic`; confirm only the generated
   analyze/fix/check transform+positive assertions are red, meta gates green (including the new
   §3b gates).
4. Delete the throwaway files; `mix test` fully green again; `mix format --check-formatted` clean.
5. `test/generator_meta_test.exs` passes (pin); the six refactored Pattern meta tests still pass
   unchanged over the real rule tree (delegation is behaviour-preserving); the new §3b gates
   pass over the retrofitted Syntax/Semantic tree.

## Implementation steps

**Phase A — Name + scaffold core**
1. Create `lib/rule_name.ex` (derive/test_module/test_path).
2. Create `lib/rule_scaffold.ex`: the three type template sets, returning `[{path, content}]`
   from `files/2`, using `RuleName`.
3. Create `lib/mix/tasks/credence.gen.rule.ex`: arg/type parsing, collision-abort, write,
   `mix format` the paths, print created paths + honest-red notice.

**Phase B — Smoke-test the generator (throwaway)**
4. Run `mix credence.gen.rule NoExampleScaffold`; `mix test`; confirm exactly the expected reds
   + all meta gates green. Repeat `--type syntax`/`--type semantic`. Delete the throwaway files.

**Phase C — Unify Pattern predicates (behaviour-preserving)**
5. Move the local predicates from the six Pattern gates into `meta_test_support.ex` (§3a);
   route `test_path` + completeness path/module through `RuleName`; switch `equivalence_meta` to
   `MetaTestSupport.load_ast/1` (drops `Code.string_to_quoted`). `mix test` → all green.

**Phase D — Syntax/Semantic gates + retrofit (NOT behaviour-preserving)**
6. Create `test/syntax_meta_test.exs` + `test/semantic_meta_test.exs` (§3b) with predicates in
   `MetaTestSupport`.
7. Retrofit existing Syntax/Semantic tests to compliance (§3c). For any rule that cannot comply
   without a behavior change: **stop and report it** (decision b). `mix test` → green.

**Phase E — Pin**
8. Create `test/generator_meta_test.exs`: per type, parse `RuleScaffold.files/2` output
   in-memory and assert every shared `MetaTestSupport` predicate passes (§4).

**Phase F — Docs**
9. README `## Writing your own rules`: add the generator lead-in.
10. CONTEXT `## Adding a Pattern rule — checklist`: add step 0; refresh stale step 4; note §3b.
11. CHANGELOG: one-line entry.

**Phase G — Final check**
12. `mix test` (fully green), `mix format --check-formatted`, `mix compile --warnings-as-errors`
    (sanity — the templates and new modules compile warning-free).

## Unresolved questions

None blocking. Two judgment calls deferred to implementation, both already directed by locked
decisions:
- The exact list of existing Syntax/Semantic rules needing a retrofit line vs. a behavior
  report (decision b) is discovered while doing Phase D step 7 — reported as encountered.
- Fix-output-validity gate (#5) was a **follow-up** and has since shipped — a
  `valid_syntax?(fix(x))` gate for both rounds (see §3b; `compiles?` rejected as
  empirically false for correct fragment-fixture fixes).
