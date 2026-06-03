# Plan: Safety switches (assumption flags) for Credence

## Context

Credence's policy is "a fix preserves behaviour for *every* input or the rule doesn't exist."
That kills a class of rules that are behaviour-identical for the overwhelming majority of
real code but diverge on rare Unicode edges (NFD text, ZWJ emoji, flags). Credence's audience
is devs fixing LLM-generated Phoenix code — overwhelmingly ASCII/simple-NFC. The absolute
guarantee leaves real value on the table (≥2 rules already deleted on this axis; a 3rd under
review now: `avoid_graphemes_enum_count_with_predicate`).

Solution: named **assumption switches**. A rule declares assumptions its fix relies on. Each
assumption is a project-wide flag, default ON (assumption accepted → rule runs). Disabling a
flag removes its rules wholesale. Autofix-only (no warn mode). A switch is **never** a
substitute for static narrowing — it only covers residual divergence that can't be detected
from the AST.

Confirmed decisions: framing = **assumption** (`assume`, default on); opts key `:assumptions`
as a sparse `%{atom => bool}` override; first switch = **`single_codepoint_graphemes`**; scope
= build mechanism **and** adopt the current rule as the first example.

## Mechanism

**1. Declare per-rule — new injected/overridable callback (mirrors `priority/0`).**
`lib/pattern/rule.ex`: add `@callback assumptions() :: [atom()]`; in `__using__` inject
`def assumptions, do: []` + `defoverridable assumptions: 0`. Document beside `priority/0`.
Rules with no override → `[]` → never filtered (backward-compat guarantee).

**2. Central registry — new module `lib/assumptions.ex` (`Credence.Assumptions`).**
Single source of truth: `@registry %{atom => %{default: bool, summary, detail}}`.
Functions: `all/0`, `names/0`, `defaults/0` (→ `%{atom => bool}`), `known?/1`,
`validate!/1` (raises `ArgumentError` on unknown override keys — a typo must not silently
become a no-op). Seed entry:
```
single_codepoint_graphemes: %{default: true,
  summary: "Every grapheme in input strings is a single codepoint.",
  detail: "True for ASCII / simple NFC. False for NFD, ZWJ emoji, flags, skin-tone
           modifiers. Rules rewriting grapheme-equality to a codepoint/binary op are
           identical only under this assumption."}
```

**3. Filter at the single chokepoint — `lib/pattern.ex` `rules/1`.**
Both `analyze/2` and `fix_with_trace/2` already route through `rules/1`, so filtering there
makes check and fix agree by construction.
```
defp rules(opts) do
  Keyword.get(opts, :rules, default_rules())
  |> RuleHelpers.filter_by_assumptions(opts)
end
```
New `RuleHelpers.filter_by_assumptions/2` (next to `discover_rules/1` in `lib/rule_helpers.ex`):
- `override = Keyword.get(opts, :assumptions, %{})`; `Assumptions.validate!(override)`
- `enabled = Map.merge(Assumptions.defaults(), override)`
- keep rule iff `Enum.all?(rule.assumptions(), &Map.get(enabled, &1, false))`
  — unknown atom in a *rule* fails **closed** (dropped); unknown atom in an *override* raises.
- Filter applies even when caller passes explicit `:rules` (consistent; documented).

**4. Transparency — minimal.** One `Logger.debug("[credence_fix] assumptions disabled: ...,
N rule(s) skipped")` in `fix_with_trace/2` when any flag is off. Do **not** touch the
`applied_rules` trace shape. (Future `skipped_rules/1` query = deferred.)

**5. Scope — Pattern only.** Syntax/Semantic have no assumption-class rules; don't add the
callback there. Helper is generic, so wiring a 3rd phase later is trivial.

## Adopt the motivating rule

`lib/pattern/avoid_graphemes_enum_count_with_predicate.ex` rewrites
`Enum.count(String.graphemes(s), &(&1 == lit))` → `String.count(s, lit)`. Two divergence
classes — handle separately:
- **(a) Static ASCII bugs** (`lit` empty or multi-char: `String.count` is substring-count, not
  element-equality — wrong even on `"abab"`). **Narrow away** in both `check` and `fix_patches`:
  fire only when `lit` is a **single codepoint** (one-codepoint ⇒ one grapheme; drops `""` and
  `"ab"`). This is unconditional, switch-independent.
- **(b) Residual** single-char-literal divergence on multi-codepoint-grapheme input → exactly
  `single_codepoint_graphemes`. After (a), add `def assumptions, do: [:single_codepoint_graphemes]`.

Net: ships ON by default; a purist disabling the flag removes it cleanly.

## Files

New:
- `lib/assumptions.ex` — registry
- `docs/safety-switches.md` — concept + registry table (rendered from `Assumptions.all/0`) +
  `:assumptions` opts example + "narrow first, then tag" author rule + fail-closed/raise semantics
- `test/assumptions_test.exs`, `test/pattern/assumptions_filtering_test.exs`

Modified — lib:
- `lib/pattern/rule.ex` (callback + default), `lib/rule_helpers.ex` (`filter_by_assumptions/2`),
  `lib/pattern.ex` (`rules/1` filter + debug log),
  `lib/pattern/avoid_graphemes_enum_count_with_predicate.ex` (narrow + tag)

Modified — tests:
- the rule's `_check_test.exs` / `_fix_test.exs`: add negatives pinning empty/multi-char `lit`
  as no-issue / `fix == code` **at default-ON** (proves narrowing, not the switch, kills them)

Modified — docs (policy, all reused as single sources of truth):
- `README.md` — "Safety switches" subsection + link, beside the existing `rules:` example
- `CONTEXT.md` Project policy — switches are the sanctioned mechanism; narrow all static
  divergence first; switches default ON; never an excuse to ship a statically-detectable bug
- `prompt.md` — amend codepoint↔grapheme bullet: ban stands; sole escape = tag with an existing
  registry assumption after full narrowing; generator must not invent switches or paper over
  static bugs
- `docs/rule-review-process.md` — new decision-table row: "safe except a residual,
  statically-undetectable, overwhelmingly-true assumption → narrow, then tag switch (default
  ON)"; cite this rule as worked example

## Verification

- `mix test` — full suite green (auto-discovered rules run in integration; confirms backward-compat).
- New filtering tests via public API:
  - default: `Credence.analyze`/`fix` fire on the snippet;
  - `assumptions: %{single_codepoint_graphemes: false}`: `analyze` → no issue **and** `fix` →
    unchanged (check+fix removed together);
  - no-assumption rule unaffected by any override; unknown override key raises.
- Behaviour proof for the adopted rule (the audit the original tests lacked): in `iex`, for
  single-codepoint `lit` over ASCII inputs assert
  `Enum.count(String.graphemes(s), &(&1==lit)) == String.count(s, lit)`; keep NFD/emoji as
  documented assumed-away negatives.
- `Credence.Assumptions.defaults/0` shape test; `validate!/1` raise test.

## Unresolved questions

1. `docs/safety-switches.md` filename ok, or fold into an existing doc?
2. Confirm explicit `:rules` + `:assumptions` should still filter (plan assumes yes).
3. Adopt the same switch retroactively for any of the already-deleted grapheme rules in
   `docs/unfixable_rules/`, or leave them archived for now?
