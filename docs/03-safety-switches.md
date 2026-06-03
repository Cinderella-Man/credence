# Plan: Safety switches for Credence

## What this is, in one breath
Credence only keeps a rule if that rule gives the **exact same answer as the original
code, for every possible input**. That strict bar makes us delete useful rules that would
only ever differ on very rare text — accented letters typed the unusual way, emoji, flag
characters — text that the people we help (LLM-written Phoenix apps) basically never feed
through their code. This plan adds **safety switches** so we can keep those rules. Ship as
**0.7.0**.

## The big idea: a switch is a promise about your data

A **switch** is a promise about the text your code will handle while it runs.

Our first switch is `single_codepoint_graphemes`. Turning it on is you saying:

> "Every character in the text my code processes is a normal, single-piece character.
> No accented letters built from two pieces (the letter plus a separate accent mark),
> no emoji, no flag symbols."

Some rules only give the same answer as your original code **if that promise is true**.
Turn the promise off, and those rules would change what your code does on rare text — so
without switches we just delete them. With switches, the rule says which promise it needs,
and it only runs when that promise is on.

There are two ways to run Credence:

- **Play-it-safe mode (`:strict`)** — Credence makes **no** promises. It only runs rules
  that are always correct, for every possible input. You get the exact same behaviour you
  had before, guaranteed.
- **Helpful mode (the default)** — Credence turns on a small set of promises that are true
  for almost all real code our users write. This lets it also run the extra rules, which is
  correct for ~99% of real code.

Plain words only. No "gated", no "ungated" — just "the promise is on" or "the promise is off".

## Important: the promise is about your *running data*, not your *source code*

The promise is about the text your program actually handles **while it runs** — names, chat
messages, file contents — not about the characters in your `.ex` files.

This matters because the difference shows up on data, not code. Example — counting the
letter "e":

```elixir
nfd = "e" <> <<0x301::utf8>>          # "é" typed the unusual way (an "e" plus a separate accent)
String.graphemes(nfd) |> Enum.count(&(&1 == "e"))   # => 0
String.count(nfd, "e")                              # => 1   ← different answer!
```

Both ways of writing it look fine. They only disagree because the *data* had an unusual
character. So when we explain the switch — in the README and in the switch's own
description — we say plainly: **"on by default, Credence assumes the text your code handles
while running is all normal single-piece characters; if you process arbitrary Unicode, pass
`assumptions: :strict`."** We do **not** say "your code is ASCII" — that's the wrong thing
to promise about.

---

# The decisions, and why we made each one

This is the heart of the plan. Every choice below is written as: **the decision**, then
**why** we made it, then (where it helps) **instead of** — the option we turned down and
what goes wrong with it — and a **concrete** example. If you only read one section, read
this one: it's the reasoning you'd otherwise have to reconstruct later.

## 1. Build the feature at all

**Decision.** Add safety switches instead of living with the strict bar as-is.

**Why.** The strict "same answer for every input" bar is doing real damage: it deletes
rules that are correct for essentially every input our users will ever feed, and wrong only
on rare Unicode they never produce. Deleting such a rule helps nobody and costs everybody a
genuinely useful fix.

**Concrete.** A rule that turns `String.graphemes(s) |> Enum.count(&(&1 == "e"))` into
`String.count(s, "e")` is a real improvement — but the two disagree on the decomposed-accent
input above. Under the strict bar we must delete it, so *no one* gets the cleanup, not even
the 99.9% of apps whose data never contains a decomposed accent. The switch lets those apps
keep the fix while the rare-Unicode app opts out.

## 2. Two modes — `:strict` and the helpful default

**Decision.** `:strict` = no promises, only always-safe rules. Default = a small curated set
of promises is on. Plain words for both; never "gated/ungated".

**Why.** The two audiences are genuinely different and both are right. An app that handles
arbitrary user text — chat with emoji, names with combining accents — needs the iron-clad
guarantee. A typical LLM-generated CRUD app handles simple text and just wants the cleanups.
One default can't serve both, so we make the safe behaviour reachable with a single word and
help everyone else by default.

**Instead of *always strict*:** everybody loses the useful rules forever, which is the
problem we're trying to solve. **Instead of *always helpful with no escape hatch*:** the
Unicode-heavy app gets its behaviour silently changed on rare input — exactly the kind of
"correct for the common case" trap the project forbids. The opt-out switch is what makes the
helpful default honest.

## 3. A switch is the smallest, simplest, checkable promise — shared, flat

**Decision.** A switch is the *weakest* promise about the data that makes a rewrite safe,
phrased as something you can actually check about your text. Switches are shared between
rules and live in one flat list of independent on/off flags. We only add a new switch when a
rule needs a promise no existing switch already covers.

**Why "smallest/weakest".** A broad promise over-claims. It would switch off rules that only
needed a weaker promise, and it would be a lie for apps it shouldn't exclude.

**Instead of a broad "text is ASCII" promise:** that's both too strong and the wrong shape.
An app with users named `José` or `Łukasz` is *not* ASCII, yet its characters are still all
single-piece, so the rewrites are still safe for it. `single_codepoint_graphemes` ("every
character is one piece") is the precise promise; "ASCII" would wrongly exclude every app with
an accented name.

**Why shared and flat.** If two rules need the same promise, they must name the *same* switch
so the user flips one flag, not two, and so "what did I promise?" stays a short list.

**Instead of a nested/hierarchical scheme:** nesting buys nothing here — independent flags
already compose by AND (next decision) — and it makes both the mental model and the code
harder. Flat wins until a real need for structure appears.

## 4. None / one / several promises (AND); same promises every firing — split mixed rules

**Decision.** A rule needs zero, one, or several promises; if several, **all** must be on
for it to run. And a rule must need the *same* promises every single time it changes code —
if one kind of change it makes is always safe but another needs a promise, **split it into
two rules.**

**Why AND.** A rule is only safe when *every* promise it relies on holds. If any one is off,
it must not run — anything else would let it fire in a state where it isn't proven safe.

**Why split mixed rules — and what breaks if you don't.** Take the manual string-reverse
rule. It rewrites two shapes to `String.reverse`:

```elixir
# always safe: grapheme space → grapheme space
String.graphemes(s) |> Enum.reverse() |> Enum.join()   →   String.reverse(s)

# needs the promise: codepoint space, flips on a decomposed accent
String.codepoints(s) |> Enum.reverse() |> IO.iodata_to_binary()   →   String.reverse(s)
```

If we kept these as one rule tagged `assumptions: [:single_codepoint_graphemes]`, then in
`:strict` mode the *whole* rule turns off — and strict users lose the **graphemes** fix,
which was always safe and never needed a promise. Splitting means strict users still get the
always-safe half. The promise should cost you exactly the rules that actually need it, and no
more.

## 5. Defaults come from real data, not Elixir habit

**Decision.** Pick each default from what our users' running data actually looks like — not
from what Elixir's standard library defaults to. `single_codepoint_graphemes` is **on**.

**Why.** Elixir's `String` module is grapheme-aware by default because Elixir is a
general-purpose language serving every locale and every kind of text. Our users are a
narrower group: LLM-generated Phoenix apps whose data is overwhelmingly plain, single-piece
text. Choosing the default from *their* data is precisely what makes helpful mode correct for
~99%+ of real code. Copying Elixir's general-purpose default here would switch the useful
rules off for almost everyone, for the sake of input almost none of them ever see.

## 6. The completeness promise — the heart of the safety story

**Decision.** Two halves, both required:
- If a rule needs a promise, then whenever that promise is true its rewrite gives the **exact
  same answer** as the original — for *every* input that keeps the promise.
- When any promise it needs is off, the rule must **not run at all**.

**Why both halves.** The first half is correctness while the promise holds. The second half
is what makes `:strict` *trustworthy*: with every promise off, only always-safe rules are
left — and that's something we can state and prove, not just hope. Drop the second half and
`:strict` stops being a real guarantee.

### 6a. Shrink the rule first, lean on a promise second

**Decision.** Before relying on a promise, narrow the rule so it only touches code that's
genuinely safe. A promise may only cover the leftover *rare-text* difference — never paper
over a plain bug we could have caught by reading the code.

**Why.** A promise is a narrow tool for one specific gap (single-piece vs multi-piece text).
If you let it stand in for "this rule is roughly right," it starts hiding ordinary bugs that
have nothing to do with Unicode.

**Concrete.** `avoid_graphemes_enum_count_with_predicate` first narrows `check` and `fix` to
a **single-character literal** (checked with `length(String.to_charlist(lit)) == 1`). That
narrowing alone drops `""`, `"ab"`, and the two-piece form of `"é"`, and keeps `"a"`, `" "`,
and the normal one-piece `"é"`. *After* narrowing, the only remaining difference between old
and new is the rare decomposed-accent case — and *that* is what the promise covers. Without
the narrowing, the promise would be masking cases that are simply wrong, not rare.

### 6b. Prove it with a property test

**Decision.** Every rule that needs a promise ships with a test that throws thousands of
random strings at both the old code and the fixed code and checks they always agree.

**Why.** Human reasoning about Unicode edge cases is exactly where we make mistakes — it's
easy to convince yourself a rewrite is safe and miss a case. A property test that generates
thousands of promise-satisfying strings and compares old-vs-fixed is the real proof. A
green example-based test only proves the handful of cases you happened to think of.

## 7. How you set switches: a small map *or* `:strict`

**Decision.** You pass `assumptions:` as either a small map naming only the switches you want
to change — `%{single_codepoint_graphemes: false}` — or the single word `:strict`, meaning
"turn every promise off".

**Why the sparse map.** You name only what you're changing; everything else keeps its
default. You don't have to know or restate the full switch list to flip one flag.

**Why `:strict` as one word.** "Turn everything off" is the common careful case, and it
shouldn't require listing every switch by hand — that's tedious *and* it would silently break
the day we add a new switch (your hand-written list wouldn't include it). One word stays
correct forever.

## 8. Three places to set switches; later wins; a missing place does nothing

**Decision.** Credence reads, in order: (1) built-in defaults, (2) `config :credence` in the
app config, (3) options passed into the call. The later one wins. A place that isn't set is
simply skipped.

**Why three.** They map to three real scopes: sensible behaviour out of the box (defaults), a
project-wide policy (config), and a one-off override (call options). Later-wins lets a single
call override the project policy, which overrides the defaults.

**Why "missing = skip".** So partial configuration never crashes — you set only what you care
about and the rest falls through to the layer beneath.

**Concrete.** A Unicode-heavy project sets `config :credence, assumptions: :strict` once. A
single batch script that it trusts can still pass
`assumptions: %{single_codepoint_graphemes: true}` to re-enable that one switch for that one
run, without touching the project config.

## 9. The switch filter always applies — even with an explicit `rules:` list

**Decision.** The base rule list always runs through the switch filter, even when the caller
hands Credence an explicit `rules:` list.

**Why.** One filter, one path, one mental model — and one safety hole closed. If passing
`rules:` bypassed the filter, a user could accidentally run a rule that's unsafe for *their*
data just by naming it, which would quietly defeat the whole safety story. The filter is not
optional dressing; it's the guarantee.

## 10. `rule_status/1` lists every rule and its missing promises

**Decision.** `Credence.Pattern.rule_status(opts)` returns, for **every** rule Credence
found: its name, which promises it needs, whether it's on right now, and which needed
promises are off. `enabled_rules/1` is just the on-names from that list.

**Why.** Trust needs visibility. Users need one place to answer "what did I promise, and what
did that turn on or off?" and to debug "why didn't this rule fire?" — at a glance, without
reading source. Deriving `enabled_rules/1` from the same list keeps the two answers from ever
disagreeing.

## 11. A wrong switch name: your typo vs. a rule's typo

**Decision.**
- **You** name a switch that doesn't exist (in options you pass) → Credence **stops with a
  clear error**.
- A **rule** names a switch that doesn't exist → Credence turns that **whole rule off**,
  logs a warning, shows it as off in `rule_status` with the bad name under its missing
  promises, and a CI test catches it before release.

**Why the asymmetry.** A user naming a bad switch is an interactive mistake happening right
now — failing fast and loud is the kindest thing; you fix the typo and move on. A rule naming
a bad switch must *not* crash the user's whole run over a library bug — but Credence also must
not run a rule whose promise it can't even understand. So it turns that one rule off (safe),
warns (visible), and a CI meta-test turns the typo into a red build before it ever ships.

**Why turn off the *whole* rule, not just drop the bad name.** Dropping the unknown promise
and running the rule anyway would run it in a state we can't prove safe — the opposite of the
point. An unknown promise is treated as a promise that can never be satisfied.

## 12. The two example rules, narrowed and verified

**Decision.** Adopt exactly two example rules.

1. **`avoid_graphemes_enum_count_with_predicate`** — narrow `check` and `fix` to a single-piece
   literal character (`length(String.to_charlist(lit)) == 1`; verified to drop `""`, `"ab"`,
   and the two-piece `"é"`, and to keep `"a"`, `" "`, and the one-piece `"é"`). A shared
   `single_codepoint?/1` helper keeps `check` and `fix` in agreement. Tag it
   `def assumptions, do: [:single_codepoint_graphemes]`.

2. **`no_manual_string_reverse`** — split in two (see decision 4): the **graphemes** version
   stays always-safe and needs no promise; the **codepoints** version becomes a new rule
   needing `[:single_codepoint_graphemes]`. Name TBD, e.g. `no_codepoint_string_reverse`.

**Why these two.** They're the smallest pair that exercises the whole design: #1 shows
shrink-first-then-promise (6a) on a single rule, and #2 shows the split-mixed-rules rule (4)
where one half needs a promise and the other doesn't. Both come from the `evolution` branch
(`/home/car/projects/credence_evolution`) with their tests.

## 13. The generator and `prompt.md` are out of scope

**Decision.** Don't touch the rule generator or `prompt.md` in this change.

**Why.** They're a separate external tool. Keeping them out keeps this change focused on the
switch mechanism and its two example rules — one reviewable unit instead of two tangled ones.

## 14. Say the default helps most people — and that the promise is about *running data*

**Decision.** State plainly, in the README and the switch's own description, that the default
helps almost everyone, and that the promise is about the text the program *handles while
running*, not the characters in the source file.

**Why.** The single most dangerous misunderstanding is thinking the switch is about the
characters in your `.ex` file. It isn't — and the `nfd` counting example above shows why: the
disagreement appears only on the *data* the program processes. If we don't say this in plain
words, a careful user will promise the wrong thing and either over-restrict or, worse,
mis-trust the guarantee.

## 15. No reviving the deleted charlist rules — type changes can't be promised away

**Decision.** Do **not** bring back the archived charlist rules. A switch can rescue a rule
whose only leftover difference is rare text; it can **not** rescue a rule that changes a
value's *type*.

**Why.** A switch is a promise about *data*. No promise about data can make a number and a
string interchangeable.

**Concrete.** `Enum.at(String.to_charlist(s), i)` returns an **integer**; `String.at(s, i)`
returns a **string**. That's a type change, true for *every* input including plain ASCII — no
amount of "the data is simple" makes them equal. These stay deleted; switches are not for
them.

## 16. Add a `CHANGELOG.md` and ship `0.7.0`

**Decision.** Add a changelog, and require a changelog line for any new on-by-default switch
or any rule that becomes on-by-default.

**Why.** The helpful default can now *change what Credence does* between versions. The day we
add a new default-on switch, an app that upgrades could see its code rewritten in a new way.
That's a behaviour change tied to a version, so it must be written down where upgraders look —
which is exactly what a changelog is for.

## 17. Switch docs live in the `Credence.Assumptions` `@moduledoc`

**Decision.** The authoritative reference is the `@moduledoc` on `Credence.Assumptions`, next
to the list of switches. `ex_doc` renders it; the README links to it. No separate switches
document beyond this plan and that moduledoc.

**Why.** Docs that sit next to the thing they describe get edited together and don't drift.
Put the switch list in one file and its description in another and they go out of sync the
first time someone adds a switch. One source of truth, rendered by the tool people already
read.

## 18. The required property test is enforced by CI, not by trust

**Decision.** A meta-test asserts that every rule with a non-empty `assumptions/0` has a
matching `Credence.Pattern.<Rule>PropertyTest` module (in
`test/pattern/<rule>_property_test.exs`).

**Why.** "Remember to write a property test" is exactly the kind of rule humans forget under
deadline. A meta-test that checks the property test *exists* turns "tagged with a switch but
never proven safe" into a **red build** instead of a silent hole. It can't judge whether the
test is *good* — but it makes the gap impossible to merge by accident, the same bar we set
for the unknown-switch CI check (decision 11).

---

## What we build, file by file

- **`lib/pattern/rule.ex`** — add `@callback assumptions() :: [atom()]`. In `__using__`,
  give every rule a default `def assumptions, do: []` plus `defoverridable assumptions: 0`
  (same shape as `priority/0`). A rule that doesn't override it needs no promises and is
  never filtered out — so nothing that exists today changes. *(This default-of-`[]` is what
  makes the whole feature backward-compatible: every current rule keeps running untouched.)*

- **`lib/assumptions.ex` (new) `Credence.Assumptions`** — the list of all known switches:
  `@registry %{atom => %{default, summary}}`. Helpers: `all/0`, `names/0`, `defaults/0`,
  `known?/1`, `validate!/1` (stops with an error on an unknown name). Its `@moduledoc` is the
  user reference: how to set switches, what `:strict` means, the three-places order,
  `config :credence`, `rule_status/1`, and a plain-words description of each switch (the
  description talks about *running data*, per the section above). First switch:
  `single_codepoint_graphemes`, on by default.

- **`lib/rule_helpers.ex`** — the plumbing:
  - `effective_assumptions(opts)` — reads `Application.get_env(:credence, :assumptions, %{})`,
    combines the three places (defaults, then config, then call options), understands
    `:strict`, and checks the names with `validate!`.
  - `filter_by_assumptions(rules, opts)` — keeps only the rules whose every needed promise is
    on. A rule that names an unknown switch is treated as having a promise that can never be
    satisfied, so it is turned off (and a warning is logged).
  - `rule_enabled?/2`.

- **`lib/pattern.ex`** — `rules/1` runs the base list through `filter_by_assumptions/2` (this
  is what makes the filter apply even to an explicit `rules:` list). Add `rule_status/1` and
  `enabled_rules/1`. In `fix_with_trace/2`, log which switches are off at debug level.

## New and changed files

**New:** `lib/assumptions.ex`; the split-out codepoint-reverse rule and its test;
`CHANGELOG.md`; `test/assumptions_test.exs`; `test/pattern/assumptions_filtering_test.exs`;
the shared random-string generator (e.g. `test/support/assumption_generators.ex`).

**Changed — code:** `lib/pattern/rule.ex`, `lib/rule_helpers.ex`, `lib/pattern.ex`,
`lib/pattern/avoid_graphemes_enum_count_with_predicate.ex`,
`lib/pattern/no_manual_string_reverse.ex`.

**Changed — dependencies:** add `{:stream_data, "~> 1.0", only: :test}` to `mix.exs`; bump the
version to 0.7.0.

**Changed — docs:** `README.md` (a short section, the plain "this is about your running data"
sentence, and a link); `CONTEXT.md` (the two modes; shrink-the-rule-first; reuse the smallest
existing promise; the property-test requirement; the changelog rule; and a note that turning
text-piece counts into character counts is **not allowed unless** it's behind
`single_codepoint_graphemes` after shrinking and with a property test);
`docs/02_rule-review-process.md` (a row in the decision table plus this as a worked example);
`docs/unfixable_rules/README.md` (one line: a switch can bring back a rule whose only leftover
difference is a registered promise; type changes are still excluded).

## The random-string generator (how we prove safety)

The property tests need random strings that **only** ever satisfy the promise — every
character one single piece. The catch: the popular presets don't do this, and *why* they
fail is the whole reason we hand-build our own.

- `StreamData.string(:ascii)` — safe, but never produces an accented letter, so it never
  tests the interesting case. Passes for free, proves little.
- `StreamData.string(:printable)` / `:utf8` — these build text one piece at a time, so sooner
  or later they emit a stray accent mark that joins onto the previous letter, making a
  two-piece character. That breaks the promise, the old and new code legitimately differ, and
  the test fails for the wrong reason.

So we build the generator from a **hand-picked set of single-piece characters** —
`StreamData.string/2` accepts a list of character ranges:

```elixir
# shared generator — every character is one single piece, by construction
def single_codepoint_string do
  StreamData.string([?\s..?~, 0xC0..0xD6, 0xD8..0xF6, 0xF8..0xFF])
  # printable ASCII + the ready-made accented letters À–ÿ, with no separate accent marks
end
```

Every character in that set already stands on its own, so no matter how you string them
together you can never form a two-piece character — the promise holds **by construction**,
and the text still reaches past plain ASCII into `é ñ ü`. (That "past plain ASCII" part is
the point: an ASCII-only generator would pass without ever exercising the accented-letter
case the promise is actually about.) One definition, in `test/support`, shared by every rule
that needs this switch.

Plus a tiny **honesty check**: a test asserting that everything this generator produces really
is single-piece (every grapheme one codepoint). The character ranges are easy to fat-finger,
and this stops a broken generator from making all the safety proofs pass for nothing — a
broken generator would otherwise turn every property test green while proving nothing.

## Tests

- **`assumptions_test`** — the shape of `defaults/0`; `validate!` stops on an unknown name;
  `single_codepoint_graphemes` is on by default.
- **`assumptions_filtering_test`** (through the public API) — default: tagged rules run;
  `assumptions: %{single_codepoint_graphemes: false}`: no issue reported **and** `fix` leaves
  the code untouched; `:strict`: only no-promise rules run; a no-promise rule is unaffected;
  an unknown name you pass stops with an error; the `config :credence` place is respected and
  the call options can override it; a missing config place does nothing. *(This single test
  file checks decisions 2, 6, 7, 8, 9, and 11 end-to-end through the real public API.)*
- **Whole-suite check** — every rule's `assumptions/0` only names real switches
  (`⊆ Assumptions.names()`). *(The teeth on decision 11's rule-typo case.)*
- **Whole-suite check (the teeth on "every promised rule is proven")** — for every rule that
  names a switch, a property-test exists for it. We use a naming convention so this is
  checkable in CI: each such rule has a module like `Credence.Pattern.<Rule>PropertyTest` (in
  `test/pattern/<rule>_property_test.exs`), and a meta-test asserts that module loads for
  every rule with a non-empty `assumptions/0`. It can't judge whether the test is *good*, but
  it turns "tagged with a switch but never proven" into a **red build** instead of a silent
  hole. *(This is decision 18.)*
- **Per example rule** — the property test (StreamData, shared generator): old vs fixed agree
  across thousands of random single-piece strings; the two-piece / emoji cases are written
  down as known differences; the cases we shrank away are pinned as "no issue" at the default
  setting. *(This is the proof behind decisions 6a and 6b.)*
- **`rule_status/1`** — every rule listed with the right on/off and missing-promise values
  under different options. *(Decision 10.)*

## How we check it works

`mix test` green (rules are found automatically, which confirms nothing old broke).
By hand: with default settings, `Credence.fix` rewrites the two example rules; with
`assumptions: :strict` it leaves them alone;
`Credence.Pattern.rule_status(assumptions: %{single_codepoint_graphemes: false})` shows them
off, with `single_codepoint_graphemes` listed as their missing promise. The property tests are
the real proof of safety.

## Not doing now (deferred)

The three-places order is kept simple on purpose. `no_grapheme_palindrome_check` (its
`to_charlist` path) would be a strong **third** example, but it's mid-rework in the current
diff — a follow-up, not this change. A `mix` task to print the switch list — later if wanted.

## Decision log (quick index)

Each line points to the full reasoning above.

1. Build the feature (§1). 2. Two modes, plain words (§2). 3. Smallest shared promise; flat
list (§3). 4. None/one/several promises + split mixed rules (§4). 5. Defaults from real data,
not Elixir habit (§5). 6. The completeness promise, both halves (§6); shrink first (§6a);
required property test (§6b). 7. Value is a small map **or** `:strict` (§7). 8. Three places,
later wins, missing place is a no-op (§8). 9. The filter always applies, even to explicit
`rules:` (§9). 10. `rule_status/1` lists every rule + missing promises (§10). 11. Unknown
switch: your typo raises, a rule's typo turns that rule off + warns + CI catches it (§11). 12.
Narrowed to a single-piece literal, verified (§12). 13. Generator / `prompt.md` out of scope
(§13). 14. Say the default helps most, and the promise is about *running data* (§14). 15. No
reviving the deleted charlist rules — type changes can't be promised away (§15). 16. Add
`CHANGELOG.md`, ship `0.7.0` (§16). 17. Switch docs live in the `Credence.Assumptions`
`@moduledoc` (§17). 18. The required property test is enforced by a CI meta-test, not by
trust (§18).
