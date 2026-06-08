# Rule scaffolding generator + contract pin

## Context

Writing a new Credence rule means re-discovering an unwritten contract by tripping
~8 meta tests one failure at a time (triplet naming, positive+negative check cases,
whole-string `==` fix, heredoc-only fixtures, no direct parser calls, equivalence
shape, assumptions wiring). The contract is *enforced* well but never *stated* in one
place — candidate 1 from the architecture review (a locality problem: the "what a valid
rule-test looks like" interface is shallow-spread across 8 files).

Fix: a deterministic generator that **embodies** the contract as a template, emitting a
correctly-shaped rule + its test files for any round. The AI/human then fills the blanks.
A pin meta test runs the generator and asserts its output passes the same structural
predicates the real meta tests use — so the generator becomes the executable
single-source-of-truth and cannot drift from the gates silently.

Decisions locked with the user:
- **All three rounds** (Pattern / Syntax / Semantic).
- **Pin it** — a meta test gates the generator output against the contract.
- **Honest red** — stubs fail their own assertions until filled; they do NOT fake-green.
- **Ships in `lib/`** — the generator lives in `lib/` (needed at `:dev` for the Mix task)
  and ships in the hex package, idiomatic like Phoenix/Ecto generators.
- **Format output** — the Mix task runs `mix format` on the files it writes.
- **Abort on collision** — if any target file exists, write nothing (no `--force` for now).
- **Full predicate unification** — lift the structural predicates into `MetaTestSupport`
  so the pin and the real meta tests call the same code.
- **Equivalence stub is always `assert_equivalent`** — opt-out (`mark_equivalence_*`) is a
  by-hand swap for the rare cosmetic/repair rule.

## Claims verified against the code

- No `--warnings-as-errors`, no format-check test, no hard-coded rule count → a new inert
  rule + unformatted-template risk won't break unrelated tests (`mix.exs`, `test_helper.exs`).
- Auto-registration via `@behaviour` (`RuleHelpers.discover_rules/1`, `lib/rule_helpers.ex:12`);
  no registry to edit. A stub Pattern rule (`check -> []`, `fix_patches -> []`) is **inert** —
  contributes no issues/patches, so pipeline/showcase/idempotency tests are unaffected.
- Only **Pattern** rules carry the completeness/check/fix/equivalence meta gates (all iterate
  `discover_rules(Credence.Pattern.Rule)`). Syntax/Semantic rules are gated only by
  `fixture_string_escaping_test` + `no_parser_calls_in_rule_tests_test` (both scan
  `test/pattern|semantic|syntax`).
- The equivalence precheck asserts `rule_fires?` **first** (`behaviour_equivalence.ex:240`),
  so an inert stub fails there with a clear "expected … to fire on:" message (honest red).
- The four meta tests already `import Credence.MetaTestSupport`; each has only 3–4 local
  predicates to lift — extraction is mechanical and behaviour-preserving.
- The behaviour `__using__` macros inject `@behaviour` + default `priority/0` (+ `assumptions/0`
  for Pattern) — templates emit only `use Credence.<Round>.Rule`, never a bare `@behaviour`.

## Design

Split into a **pure scaffold** (returns file plans, testable without disk I/O) and a thin
**Mix task** (writes them). The pin reuses the pure scaffold.

### 1. `Credence.RuleScaffold` — pure templates (`lib/rule_scaffold.ex`, new)

Public interface (deep, small surface):

```elixir
@spec files(name :: String.t(), round :: :pattern | :syntax | :semantic)
        :: [{path :: String.t(), content :: String.t()}]
```

- `name` accepted as `NoFooBar` or `no_foo_bar`; normalize via `Macro.underscore` /
  `Macro.camelize`. Derive: snake (file/atom), Pascal (module), `Credence.<Round>.<Pascal>`.
- Returns the rule file + its test files (no writes). Templates are plain strings (the project
  already builds code as strings; no AST printing). Use parseable placeholders (`foo(bar)` /
  `baz(qux)`) so `check/2`'s `Sourceror.parse_string!` never crashes on a fixture.
- **Out of scope:** assumptions/property-test scaffolding (assumptions default to `[]`, so no
  property test is required; added by hand for the rare switched rule).

**Pattern** → 4 files:
- `lib/pattern/<snake>.ex` — `use Credence.Pattern.Rule`; `@impl true def check(_ast,_opts) -> []`
  with a `# TODO` + `:<snake>`-atom Issue example in a comment; `@impl true def fix_patches(_ast,_opts) -> []`
  (TODO points at `RuleHelpers.patches_from_postwalk/2`). Moduledoc TODO with `## Bad`/`## Good`.
- `test/pattern/<snake>_check_test.exs` — `use Credence.RuleCase, async: true`; `alias` the rule;
  one `assert flagged?(Rule, """foo(bar)""")` (positive) + one `assert clean?(Rule, """baz(qux)""")`
  (negative). Satisfies check_meta's positive+negative gate structurally; `flagged?` fails at runtime (red).
- `test/pattern/<snake>_fix_test.exs` — `use Credence.RuleCase, async: true`; one
  `assert fix(Rule, input) == expected` with **different** input/expected heredocs (satisfies
  fix_meta `transform?`); stub `fix` returns input → red.
- `test/pattern/<snake>_equivalence_test.exs` — `use Credence.RuleCase, async: true`;
  `assert_equivalent("""foo(bar)""", rule: Rule, vars: [:bar], inputs: [1, 2, 3])`
  (`assert_equivalent` is imported by `use Credence.RuleCase`). Satisfies equivalence_meta;
  precheck "rule must fire" fails on the inert stub → red.

**Syntax** → 2 files (no equivalence; not under the Pattern completeness gate):
- `lib/syntax/<snake>.ex` — `use Credence.Syntax.Rule`; `analyze(_source) -> []`; `fix(source) -> source`.
- `test/syntax/<snake>_analyze_test.exs` + `_fix_test.exs` — `use ExUnit.Case`; local
  `defp analyze/fix` wrappers calling the rule, called bare with heredoc fixtures (matches
  `fix_python_modulo_*_test.exs` so fixture-escaping sees bare `analyze`/`fix`). Stubs → red.

**Semantic** → 2 files:
- `lib/semantic/<snake>.ex` — `use Credence.Semantic.Rule`; `match?(_) -> false`;
  `to_issue/1` building `%Issue{rule: :<snake>}`; `fix(source,_) -> source`; `defp line/1`.
- `test/semantic/<snake>_check_test.exs` (synthetic diagnostic → `assert Rule.match?(diag)`) +
  `_fix_test.exs` (`fix("""broken""", diag) == """fixed"""`, heredoc fixtures). `use ExUnit.Case`. Stubs → red.

### 2. `Mix.Tasks.Credence.Gen.Rule` (`lib/mix/tasks/credence.gen.rule.ex`, new)

`mix credence.gen.rule <Name> [--round pattern|syntax|semantic]` (default `pattern`). Thin:
1. Normalize `<Name>`; resolve round.
2. `RuleScaffold.files/2` → `[{path, content}]`.
3. **Abort** (print error, write nothing) if any path already exists.
4. `File.write!/2` each; then `mix format` the written paths (`Mix.Task.run("format", paths)`).
5. Print created paths + a notice that the generated tests are **intentionally red** until
   filled (honest-red by design). No registry edit needed (auto-discovery).

### 3. Unify the structural predicates (candidate 1's deepening) — `test/support/meta_test_support.ex`

Lift the predicates currently private to the four structural meta tests into
`Credence.MetaTestSupport` (its documented role — "shared machinery for the per-rule
test-file gates") as pure `ast -> bool` functions, and have each meta test **delegate** (no
assertion-behaviour change):
- from `check_meta_test.exs`: `has_positive?/1`, `has_negative?/1` (+ `check_call?`, `check_eq_empty?`).
- from `fix_meta_test.exs`: `partial_match?/1`, `transform?/1` (+ `fix_call?`, `fix_arg`, `@banned_matchers`).
- from `fixture_string_escaping_test.exs`: `fixtures/1`, `stringish?/1`, `ok?/1`, `multiline_interp?/1`
  (+ `@verbs`, `@fvars`).
- from `equivalence_meta_test.exs`: `defines_module?/2` (+ `@assert_fns`, `@mark_fns`).
- from `no_parser_calls_in_rule_tests_test.exs`: `parser_ref?/1`.

This makes the pin drift-proof: pin and meta tests call the **same** predicate code. Folding
`equivalence_meta_test.exs` onto the shared `MetaTestSupport.load_ast/1` (Sourceror) also fixes
candidate 3 for free — it currently uses `Code.string_to_quoted` (`test/equivalence_meta_test.exs:68`),
violating the Sourceror-only policy (CONTEXT.md).

### 4. Pin meta test (`test/generator_meta_test.exs`, new)

For each round, call `RuleScaffold.files/2` with a sample name, parse each content with
Sourceror **in memory (no disk writes)**, and assert via the shared `MetaTestSupport`
predicates that the output would pass every structural gate:
- correct paths + module names (completeness convention),
- pattern check has positive+negative; fix has `transform?` + whole-string `==`; equivalence
  calls an assert and references the rule,
- all fixtures are heredocs (`fixtures/1` + `ok?/1`); no `Code`/`Sourceror` refs (`parser_ref?/1`),
- syntax/semantic: their expected shapes + heredoc fixtures + no parser refs.

### 5. Docs (small, required)

- **README.md** — under `## Writing your own rules` (line 138), add a short lead-in: run
  `mix credence.gen.rule MyRule [--round ...]` to scaffold the rule + its tests (which start
  red); then fill in the `check`/`fix`/fixtures.
- **CONTEXT.md** — `## Adding a Pattern rule — checklist`: add a step 0 ("run
  `mix credence.gen.rule <Name>` to generate the rule + check/fix/equivalence skeletons —
  correctly named, heredoc fixtures, passing the structural meta gates; assertions start red,
  fill them in"). Also refresh the now-stale step 4, which still says parse with
  `Sourceror.parse_string!/1` and call `apply_rule_fix/3` directly — replace with the RuleCase
  verbs (`check`/`flagged?`/`clean?`/`fix`).
- **CHANGELOG.md** — one line under the current version (optional but matches house style).

## Files

- **New**: `lib/rule_scaffold.ex`, `lib/mix/tasks/credence.gen.rule.ex`, `test/generator_meta_test.exs`.
- **Modified**: `test/support/meta_test_support.ex` (gains shared predicates); the four meta
  tests `check_meta_test.exs`, `fix_meta_test.exs`, `fixture_string_escaping_test.exs`,
  `equivalence_meta_test.exs` (delegate to shared predicates; equivalence switches to Sourceror);
  `README.md`, `CONTEXT.md`, `CHANGELOG.md`.

## Reuse (don't re-implement)

- `RuleHelpers.discover_rules/1` (`lib/rule_helpers.ex:12`) — auto-discovery; no registry.
- `MetaTestSupport` helpers already present: `walk_any?/2`, `count_nodes/2`, `calls_any?/2`,
  `references_rule?/2`, `src/1`, `equals_empty_list?/1`, `load_ast/1`, `short/1`, `test_path/2`, `bullets/2`.
- Behaviour modules' `__using__` inject `@behaviour` + defaults — templates emit only `use`.

## Verification

1. `mix credence.gen.rule NoExampleScaffold` → creates 4 pattern files, format-clean.
2. `mix test` → **only** the 3 generated test files are red (check `flagged?`, fix transform,
   equivalence "rule must fire"); every meta gate (completeness, check/fix/fixture/no-parser/
   equivalence) is **green**. Confirms honest-red is localized and the structural contract is met.
3. Repeat for `--round syntax` and `--round semantic`; confirm only the generated analyze/fix
   (and check) assertions are red, meta gates green.
4. Delete the throwaway files; `mix test` fully green again; `mix format --check-formatted` clean.
5. `test/generator_meta_test.exs` passes (pin), and the four refactored meta tests still pass
   unchanged over the real rule tree (delegation is behaviour-preserving).

## Implementation steps

**Phase A — Scaffold core**
1. Create `lib/rule_scaffold.ex`: name derivation (`Macro.underscore`/`Macro.camelize`) + the
   three round template sets, returning `[{path, content}]` from `files/2`.
2. Create `lib/mix/tasks/credence.gen.rule.ex`: arg/round parsing, collision-abort, write,
   `mix format` the paths, print created paths + honest-red notice.

**Phase B — Smoke-test the generator (throwaway)**
3. Run `mix credence.gen.rule NoExampleScaffold`; `mix test`; confirm exactly 3 reds + all meta
   gates green. Repeat `--round syntax` and `--round semantic`. Delete the throwaway files.

**Phase C — Unify predicates (refactor, behaviour-preserving)**
4. Move the local predicates from the 4 meta tests into `test/support/meta_test_support.ex`
   (see §3 list); export them.
5. Update `check_meta_test.exs`, `fix_meta_test.exs`, `fixture_string_escaping_test.exs`,
   `equivalence_meta_test.exs` to delegate; switch `equivalence_meta_test.exs` to
   `MetaTestSupport.load_ast/1` (drops `Code.string_to_quoted`). Run `mix test` → all green.

**Phase D — Pin**
6. Create `test/generator_meta_test.exs`: per round, parse `RuleScaffold.files/2` output
   in-memory and assert every structural predicate from `MetaTestSupport` passes.

**Phase E — Docs**
7. README `## Writing your own rules`: add the generator lead-in.
8. CONTEXT `## Adding a Pattern rule — checklist`: add step 0; refresh stale step 4 to RuleCase verbs.
9. CHANGELOG: one-line entry.

**Phase F — Final check**
10. `mix test` (fully green), `mix format --check-formatted`, `mix compile --warnings-as-errors`
    (sanity — the templates and new modules compile warning-free).
