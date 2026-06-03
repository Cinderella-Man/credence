# Plan: Safety switches (assumptions) for Credence

## Context
Credence's rule set is behaviour-preserving for *every* input, which deletes rules that are
identical except on rare Unicode inputs (NFD, emoji, flags) that the target audience
(LLM-generated Phoenix, ~ASCII/NFC) never hits. Add named **assumption switches**: a rule can
declare an assumption about input data; switches are project-wide flags with curated defaults.
Ship as **0.7.0**.

## Core model (decided)
- **`:strict` = absolute** (only no-assumption rules run → same result for every input).
  **default = curated** (also runs rules whose assumptions are on → changes behaviour on rare
  inputs, correct for ~99% of real code). Plain language only — no "gated/ungated".
- **A switch = the weakest input-data precondition** that makes a rewrite identical, phrased as a
  checkable property of input. Shared across rules. Flat, independent flags; a new switch only
  when a rule's precondition isn't implied by an existing one.
- **Rule tiers:** no assumptions / one assumption / many assumptions (**all** must be on — AND).
  **Every *firing* of a rule must need the exact same assumption set**; if parts differ, **split
  into separate rules**.
- **Defaults set by audience-data-truth, not Elixir idiom** (Elixir is grapheme-aware; we
  intentionally diverge). `single_codepoint_graphemes` defaults **true**.
- **Completeness contract:** a rule with assumptions must be identical for *every input
  satisfying them*, and must **not fire** when any is off (so `:strict` is provably absolute).
  Static divergences are narrowed away first — a switch never excuses a statically-detectable
  bug. Guard against under-declared assumptions with a **mandatory property test** (StreamData)
  that runs original-vs-fixed over **broad random** inputs satisfying the declared switches,
  drawn from a **shared per-switch generator** (rules may not hand-roll/weaken inputs).
- **Override:** opts key `:assumptions` = sparse `%{atom=>bool}` **or** the atom `:strict`.
  Layers, low→high: **registry defaults < `config :credence` < per-call opts**. Missing config
  is a no-op (never crashes). `:strict` at a layer zeroes all; a higher layer can flip specific
  ones back on.
- **Filtering always applies**, even to an explicit `rules:` list (one predicate, one path).
- **Introspection:** `Credence.Pattern.rule_status(opts) :: [%{rule, assumptions, enabled,
  missing}]` — lists **every** discovered rule with all info in one shot.
  `enabled_rules/1 = for r <- rule_status(opts), r.enabled, do: r.rule`.
- **Unknown switch:** in user override → **raise** `ArgumentError`; declared by a rule → runtime
  **drop + `Logger.warning`** (no raise), and a **suite-wide test** asserts every rule's
  `assumptions/0 ⊆ Assumptions.names()` (catches the typo in CI).
- **Out of scope:** `prompt.md` / the generator (separate external harness). No revival of the
  archived charlist rules (they change element **type** — integer↔string — which no switch fixes).
- **Versioning:** add `CHANGELOG.md`; any new default-on switch or newly-default-on rule needs a
  changelog line (default behaviour is now version-dependent).
- **Docs:** authoritative reference lives in `Credence.Assumptions` `@moduledoc` (co-located with
  the registry, edited together — least drift), rendered by `ex_doc`. README links to it. No
  separate user-facing switches doc beyond this plan + the moduledoc.

## Mechanism (file by file)
- **`lib/pattern/rule.ex`** — add `@callback assumptions() :: [atom()]`; in `__using__` inject
  `def assumptions, do: []` + `defoverridable assumptions: 0` (mirrors `priority/0`). Doc beside
  `priority/0`. No override → `[]` → never filtered (backward-compat).
- **`lib/assumptions.ex` (new) `Credence.Assumptions`** — `@registry %{atom => %{default,
  summary}}`; `all/0`, `names/0`, `defaults/0`, `known?/1`, `validate!/1` (raise on unknown).
  `@moduledoc` = the user reference (how to set switches, `:strict`, precedence, `config
  :credence`, `rule_status/1`, per-switch descriptions). Seed: `single_codepoint_graphemes`
  (default true).
- **`lib/rule_helpers.ex`** — `effective_assumptions(opts)` (read app env via
  `Application.get_env(:credence, :assumptions, %{})`, merge registry < config < opts, accept
  `:strict`, `validate!`), `filter_by_assumptions(rules, opts)`, `rule_enabled?/2`. Next to
  `discover_rules/1`.
- **`lib/pattern.ex`** — `rules/1` pipes base list through `filter_by_assumptions/2` (covers
  explicit `rules:` too). Add `rule_status/1` + `enabled_rules/1`. Debug-log disabled switches in
  `fix_with_trace/2`.

## Worked example rules (adopt both)
1. **`avoid_graphemes_enum_count_with_predicate`** — narrow `check`+`fix` to a **single-codepoint**
   literal (`length(String.to_charlist(lit)) == 1`; verified: drops `""`/`"ab"`/NFD-`"é"`, keeps
   `"a"`/`" "`/`"é"`NFC). Shared `single_codepoint?/1` so check/fix agree. Tag
   `assumptions, do: [:single_codepoint_graphemes]`.
2. **`no_manual_string_reverse`** — **split** (per homogeneity rule):
   - graphemes path (`String.graphemes |> reverse |> join`/`iodata_to_binary` → `String.reverse`)
     stays an **always-safe, no-assumption** rule (verified identical for all inputs).
   - **codepoints path** (`String.codepoints |> reverse |> IO.iodata_to_binary` → `String.reverse`)
     becomes a **new rule** tagged `[:single_codepoint_graphemes]` (verified: diverges on NFD,
     identical on ASCII; same type string→string). Name TBD (e.g. `no_codepoint_string_reverse`).

Both copied from the `evolution` branch (`/home/car/projects/credence_evolution`) with their tests.

## Files
New: `lib/assumptions.ex`; the split-out codepoint-reverse rule + test; `CHANGELOG.md`;
`test/assumptions_test.exs`; `test/pattern/assumptions_filtering_test.exs`; shared StreamData
generator helper (e.g. `test/support/assumption_generators.ex`).
Modified — lib: `lib/pattern/rule.ex`, `lib/rule_helpers.ex`, `lib/pattern.ex`,
`lib/pattern/avoid_graphemes_enum_count_with_predicate.ex`, `lib/pattern/no_manual_string_reverse.ex`.
Modified — deps: add `{:stream_data, "~> 1.0", only: :test}` to `mix.exs`; bump version 0.7.0.
Modified — docs: `README.md` (short section + link), `CONTEXT.md` (two-tier policy, narrow-first,
weakest-existing-switch, property-test, changelog rule; codepoint↔grapheme clause → forbidden
unless behind `single_codepoint_graphemes` after narrowing + test), `docs/02_rule-review-process.md`
(decision-table row + this as worked example), `docs/unfixable_rules/README.md` (one line: a
switch can revive a rule whose *only* residual is a registry assumption; type changes excluded).

## Tests
- `assumptions_test`: `defaults/0` shape; `validate!` raises on unknown; `single_codepoint_graphemes`
  default true.
- `assumptions_filtering_test` (via public API): default → tagged rules fire; `assumptions:
  %{single_codepoint_graphemes: false}` → no issue **and** `fix` unchanged; `:strict` → only
  no-assumption rules; no-assumption rule unaffected; unknown override key raises; `config
  :credence` layer respected and overridable by opts; missing config no-op.
- Suite-wide: every discovered rule's `assumptions/0 ⊆ Assumptions.names()`.
- Per adopted rule: **property test** (StreamData, shared generator) — original vs fixed identical
  over broad random single-codepoint inputs; documented NFD/emoji negatives; narrowed-away static
  cases pinned as no-issue at default-on.
- `rule_status/1`: every rule listed with correct `enabled`/`missing` under varied opts.

## Verification
`mix test` green (auto-discovered rules ⇒ confirms backward-compat). Manually: `Credence.fix`
default rewrites the two examples; `assumptions: :strict` leaves them untouched;
`Credence.Pattern.rule_status(assumptions: %{single_codepoint_graphemes: false})` shows them
`enabled: false, missing: [:single_codepoint_graphemes]`. Property tests are the behaviour proof.

## Deferred
App-env precedence kept simple. `no_grapheme_palindrome_check` `to_charlist` path = strong
**third** example but mid-rework in the current diff — follow-up, not this change. `mix` task to
print the registry — later if wanted.

## Decision log (from design grilling)
1. Feature exists. 2. Defaults = audience-data-truth, not Elixir idiom. 3. Switch = weakest shared
input-precondition; flat. 4. Three tiers + per-firing homogeneity (split mixed rules). 5. Mandatory
original-vs-fixed property test. 6. StreamData (test-only dep). 7. Value = sparse map **or**
`:strict`. 8. Three config layers (registry < `config :credence` < opts); absence is a no-op.
9. Filtering always applies, even to explicit `rules:`. 10. `rule_status/1` lists every rule +
missing switches. 11. Rule-typo'd switch → suite test catches it; runtime drops-and-warns.
12. Literal narrowed to single **codepoint** (verified). 13. Generator/`prompt.md` out of scope.
14. `CONTEXT.md` two-tier, `:strict`=absolute / default=curated; plain language. 15. No archive
revival here (type changes excluded). 16. `CHANGELOG.md`, ship `0.7.0`. 17. Switch docs in
`Credence.Assumptions` `@moduledoc`. 18. Adopt examples #1 + #2 (charlist rules rejected — they
change element type, unfixable by any switch).
