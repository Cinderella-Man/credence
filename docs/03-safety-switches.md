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

**The invariant, reframed.** We are *not* abandoning behaviour preservation — we are stating
it relative to a declared domain:

> **Credence never changes behaviour on any input your stated promises admit.**

In `:strict` you make **zero** promises, so the admitted domain is *every possible input* and
the result is bit-identical to the original code — the old iron-clad guarantee, intact and
reachable by one word. In the helpful default you make **one** checkable promise, and the
result is identical for every input that keeps it. This is not "best-effort"; it is "absolute,
relative to a stated domain." (This reframing must also be written into `CONTEXT.md` and
`docs/02_rule-review-process.md`, which today still state the old "every input, no exceptions"
wording.)

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

**The split key is the *decompose* function, not the reassemble function — get this right or
you misroute.** The reverse rule matches four shapes (either decompose paired with either
reassemble). What decides safe-vs-unsafe is the **first** function: `String.graphemes`
(sees whole characters; reversing them always equals `String.reverse`) vs `String.codepoints`
(sees the pieces; can split a decomposed accent). The reassemble function (`Enum.join` vs
`IO.iodata_to_binary`) makes **no** difference — both just glue the pieces back. Verified
empirically on a decomposed accent: `graphemes |> iodata_to_binary == String.reverse` (safe),
`codepoints |> join != String.reverse` (unsafe).

| decompose | reassemble | rule it belongs to |
|---|---|---|
| `String.graphemes` | `Enum.join` | always-safe (`no_manual_string_reverse`, no promise) |
| `String.graphemes` | `IO.iodata_to_binary` | always-safe (`no_manual_string_reverse`, no promise) |
| `String.codepoints` | `Enum.join` | promise (`no_codepoint_string_reverse`) |
| `String.codepoints` | `IO.iodata_to_binary` | promise (`no_codepoint_string_reverse`) |

The danger is routing by the *last* function (because §4's two examples happen to pair
`graphemes` with `join` and `codepoints` with `iodata`): that would let `codepoints |> join`
run with no promise — a behaviour-changing fix shipped in `:strict`. The promise rule's
property test **must** include a `codepoints |> join` case so a misroute is a red build.

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

## 7. How you set switches: a small map, `:strict`, or `:default`

**Decision.** You pass `assumptions:` as one of three things:
- a **small map** naming only the switches you want to change — `%{single_codepoint_graphemes: false}`;
- the word **`:strict`**, meaning "turn every promise off";
- the word **`:default`**, meaning "discard the lower layers and use the built-in defaults".

**The three behave as two different *kinds* of operation — this is the merge algebra:**

- **`:strict` and `:default` are full resets.** They reach **every** known switch, named or
  not: `:strict` forces all of them off; `:default` sets all of them to their registry
  default. Neither depends on what any lower layer said.
- **A small map is a patch.** It overrides **only** the keys it names; every switch it does
  *not* mention falls through unchanged to the layer below (config, then defaults). A small
  map is **never** expanded with defaults before merging — doing so would let an unmentioned
  switch silently stomp the layer beneath it.

**Why the sparse map is a patch, not a full map.** Picture two switches and a config that set
the *other* one. If your call's `%{single_codepoint_graphemes: false}` were expanded to a full
map (filling the other switch from its default), merging it over config would reset that other
switch — undoing a project-wide setting you never touched. So a small map must only patch its
own keys.

**Why `:strict` as one word.** "Turn everything off" is the common careful case, and it
shouldn't require listing every switch by hand — that's tedious *and* it would silently break
the day we add a new switch (your hand-written list wouldn't include it). One word stays
correct forever.

**Why `:default` as the mirror.** The same forever-correct argument runs in the opposite
direction: a trusted call under a `:strict` project that wants *all* the helpful behaviour back
would otherwise have to hand-list every switch — and silently miss switch #2 the day we add it.
`:default` is the one word that says "all of it, whatever the current defaults are," and stays
correct forever too. Same machinery as `:strict`, pointed at the defaults map instead of
all-off.

## 8. Three places to set switches; later wins; a missing place does nothing

**Decision.** Credence reads, in order: (1) built-in defaults, (2) `config :credence` in the
app config, (3) options passed into the call. The later one wins (call > config > defaults). A
place that isn't set is simply skipped. Mechanically: start from the full defaults map, then
fold each later layer on top using the §7 algebra — `:strict`/`:default` overwrite **all**
keys, a small map patches **only its own** keys.

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

**But name a rule and have it filtered, and you get a *visible* heads-up.** Silently dropping a
rule the caller asked for by name reads as "this rule is broken." So when a rule appears in an
**explicit** `rules:` list **and** is filtered out for a missing promise, Credence logs one
**warning**-level line naming the rule and the missing promise (e.g. `NoCodepointStringReverse
skipped: needs single_codepoint_graphemes, which is off`). It still does **not** run the rule —
the filter has no exceptions — and it does **not** crash (that would wreck the trusted-script
ergonomics and contradict "missing = skip", §8). The warning fires only for rules you
deliberately named, so the default path stays quiet.

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

2. **`no_manual_string_reverse`** — split in two **by the decompose function** (see decision
   4's four-shape table): the rule keeps **both `String.graphemes` shapes** (with either
   `Enum.join` or `IO.iodata_to_binary`), stays always-safe, needs no promise. A new rule
   **`no_codepoint_string_reverse`** takes **both `String.codepoints` shapes** and needs
   `[:single_codepoint_graphemes]`. Its property test must include a `codepoints |> join` case.

**Why these two.** They're the smallest pair that exercises the whole design: #1 shows
shrink-first-then-promise (6a) on a single rule, and #2 shows the split-mixed-rules rule (4)
where one half needs a promise and the other doesn't. Both come from the `evolution` branch
(`/home/car/projects/credence_evolution`) with their tests.

## 13. The generator is out of scope

**Decision.** Don't touch the rule generator in this change.

**Why.** It's a separate external tool. Keeping it out keeps this change focused on the
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

**And it gets teeth, not just trust.** "Require a changelog line" is the same kind of thing
§18 says humans forget under deadline — so we enforce it the same way, with the lightest check
that works: a CI step that fails if the `@registry` defaults in `lib/assumptions.ex` changed in
a commit and `CHANGELOG.md` did **not**. Like §18's property-test check, it can't judge whether
the changelog *line* is good — but it turns "shipped a default-on behaviour change with no
changelog" from possible-and-silent into a red build.

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
  user reference: how to set switches, what `:strict` and `:default` mean, the three-places
  order and merge algebra (§7), `config :credence`, `rule_status/1`, and a plain-words
  description of each switch (the description talks about *running data*, per the section
  above). First switch: `single_codepoint_graphemes`, on by default.

- **`lib/rule_helpers.ex`** — the plumbing:
  - `effective_assumptions(opts)` — reads `Application.get_env(:credence, :assumptions, %{})`,
    folds the three places (defaults → config → call options, later wins) using the §7 algebra:
    starts from the full defaults map, and for each later layer applies `:strict` (all keys
    off) or `:default` (all keys to registry default) as a **full reset**, or a small map as a
    **patch of only its named keys** (never expanded with defaults). Checks the names with
    `validate!`.
  - `filter_by_assumptions(rules, opts)` — keeps only the rules whose every needed promise is
    on. A rule that names an unknown switch is treated as having a promise that can never be
    satisfied, so it is turned off (and a warning is logged). When a filtered-out rule was named
    in an **explicit** `rules:` list, logs a **warning** naming the rule and its missing
    promise (§9) — still filtered, never crashes.
  - `rule_enabled?/2`.

- **`lib/pattern.ex`** — `rules/1` runs the base list through `filter_by_assumptions/2` (this
  is what makes the filter apply even to an explicit `rules:` list), and tells the filter
  whether the list was caller-supplied so it can warn on an explicitly-named filtered rule
  (§9). Add `rule_status/1` and `enabled_rules/1`. In `fix_with_trace/2`, log which switches
  are off at debug level.

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
sentence, and a link); `CONTEXT.md` (**rewrite the absolute "identical output for every input"
rule into the reframed invariant** — *"Credence never changes behaviour on any input your
stated promises admit"*, with `:strict` = zero promises = bit-identical; the two modes;
shrink-the-rule-first; reuse the smallest existing promise; the property-test requirement; the
changelog rule; and a note that turning text-piece counts into character counts is **not
allowed unless** it's behind `single_codepoint_graphemes` after shrinking and with a property
test); `docs/02_rule-review-process.md` (**the same reframed invariant** replacing the old
every-input wording; a row in the decision table plus this as a worked example).

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
  `single_codepoint_graphemes` is on by default; `effective_assumptions` merge algebra (§7):
  `:strict` and `:default` reset **all** keys, a small map patches **only** its named keys and
  leaves the rest to the layer below (the two-switch patch case from §7), call > config >
  defaults precedence.
- **`assumptions_filtering_test`** (through the public API) — default: tagged rules run;
  `assumptions: %{single_codepoint_graphemes: false}`: no issue reported **and** `fix` leaves
  the code untouched; `:strict`: only no-promise rules run; `:default` under a `:strict` config
  re-enables everything; a no-promise rule is unaffected; an unknown name you pass stops with an
  error; naming a filtered rule in an explicit `rules:` list logs a warning but still filters it
  (§9); the `config :credence` place is respected and the call options can override it; a
  missing config place does nothing. *(This single test file checks decisions 2, 6, 7, 8, 9,
  and 11 end-to-end through the real public API.)*
- **Changelog guard (§16 teeth)** — a CI step asserting that if the `@registry` defaults in
  `lib/assumptions.ex` changed in a commit, `CHANGELOG.md` changed too.
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
required property test (§6b). 7. Value is a small map, `:strict`, or `:default`; full-reset vs
patch merge algebra (§7). 8. Three places, later wins, missing place is a no-op (§8). 9. The
filter always applies, even to explicit `rules:`; an explicitly-named filtered rule warns (§9).
10. `rule_status/1` lists every rule + missing promises (§10). 11. Unknown switch: your typo
raises, a rule's typo turns that rule off + warns + CI catches it (§11). 12. Narrowed to a
single-codepoint literal, verified; reverse rule split by decompose function (§12). 13.
Generator out of scope (§13). 14. Say the default helps most, and the promise is about *running data* (§14). 15. No
reviving the deleted charlist rules — type changes can't be promised away (§15). 16. Add
`CHANGELOG.md`, ship `0.7.0` (§16). 17. Switch docs live in the `Credence.Assumptions`
`@moduledoc` (§17). 18. The required property test is enforced by a CI meta-test, not by
trust (§18).

---

# Concrete implementation sequence (do in this order)

Ordered so the tree stays green after every step and each step depends only on earlier
ones. Run `mix test` at the end of each phase; it must stay green. The two example rules and
their check/fix tests are ported from `evolution`
(`/home/car/projects/credence_evolution`) — bring each rule's existing tests with it.

## Phase A — Scaffolding (no behaviour change yet)
1. `mix.exs`: add `{:stream_data, "~> 1.0", only: :test}`; bump `version:` to `0.7.0`.
2. Add `CHANGELOG.md` with a `0.7.0` entry: safety switches; `single_codepoint_graphemes`
   default-on; the two example rules now fix behind the switch.
3. `lib/pattern/rule.ex`: add `@callback assumptions() :: [atom()]`; in `__using__` add
   `def assumptions, do: []` + `defoverridable assumptions: 0` (mirror `priority/0`).
   - **Done when:** `mix deps.get` succeeds and `mix test` is green — every existing rule now
     answers `assumptions/0 == []` and nothing is filtered. This proves backward-compatibility.

## Phase B — The registry
4. `lib/assumptions.ex` → `Credence.Assumptions`: `@registry %{single_codepoint_graphemes:
   %{default: true, summary: "..."}}`; helpers `all/0`, `names/0`, `defaults/0`, `known?/1`,
   `validate!/1` (raises a clear error on an unknown name). Write the `@moduledoc` (the user
   reference: setting switches, `:strict`/`:default`, the three-places order + merge algebra
   §7, `config :credence`, `rule_status/1`, plain-words per-switch description framed about
   *running data*).
5. `test/assumptions_test.exs` (registry half): `defaults/0` shape; `validate!` raises on a
   bad name; `single_codepoint_graphemes` default true.
   - **Done when:** Phase B tests green.

## Phase C — The plumbing (merge algebra + filter)
6. `lib/rule_helpers.ex`: `effective_assumptions(opts)` — fold defaults → `config :credence`
   → call `opts`, later wins, applying the §7 algebra (`:strict`/`:default` reset all keys; a
   small map patches only its named keys; never expand a small map with defaults); call
   `Assumptions.validate!` on user-named keys. `filter_by_assumptions(rules, opts, explicit?)`
   — keep rules whose every needed promise is on; an unknown switch on a rule = unsatisfiable
   ⇒ rule off + `Logger.warning`; a rule filtered out while named in an explicit `rules:` list
   ⇒ `Logger.warning` naming rule + missing promise (§9). `rule_enabled?/2`.
7. Extend `test/assumptions_test.exs` (merge half): `:strict`/`:default` reset all; small-map
   patch leaves unmentioned switches to the layer below (the two-switch §7 case — use a
   temporary second fake switch in the test or assert via a stubbed registry); precedence
   call > config > defaults.
   - **Done when:** Phase C tests green.

## Phase D — Wire into the public path
8. `lib/pattern.ex`: `rules/1` runs the base list through `filter_by_assumptions/3`, passing
   whether `rules:` was caller-supplied (for the §9 warning). Add `rule_status/1` (every
   discovered rule: name, needed promises, on/off now, which needed promises are off) and
   `enabled_rules/1` (the on-names from that list). In `fix_with_trace/2`, debug-log which
   switches are off.
   - **Done when:** `mix test` green (no rule tags a switch yet, so still a no-op end-to-end);
     `rule_status/1` returns sane data in `iex`.

## Phase E — The safety generator (needed before any property test)
9. `test/support/assumption_generators.ex`: `single_codepoint_string/0` over
   `[?\s..?~, 0xC0..0xD6, 0xD8..0xF6, 0xF8..0xFF]`.
10. Honesty test: assert every value it produces is single-codepoint (each grapheme one
    codepoint).
    - **Done when:** honesty test green.

## Phase F — Example rule #1: `avoid_graphemes_enum_count_with_predicate`
11. Port the rule from `evolution`. Narrow `check` and `fix` to a **single-codepoint literal**
    via a shared `single_codepoint?/1` helper (`length(String.to_charlist(lit)) == 1`) so
    `""`, `"ab"`, two-piece `"é"` are dropped and `"a"`, `" "`, one-piece `"é"` kept. Tag
    `def assumptions, do: [:single_codepoint_graphemes]`.
12. Port its check/fix tests; pin the shrunk-away cases as "no issue" at the default setting.
13. `test/pattern/avoid_graphemes_enum_count_with_predicate_property_test.exs`: old
    (`String.graphemes |> Enum.count(pred)`) vs fixed (`String.count`) agree across the
    generator; record the two-piece/emoji cases as known differences.
    - **Done when:** these tests green; by hand, default `fix` rewrites it, `:strict` leaves it.

## Phase G — Example rule #2: split the reverse rule
14. In `no_manual_string_reverse`, **keep both `String.graphemes` shapes** (with `Enum.join`
    or `IO.iodata_to_binary`); always-safe, no `assumptions`. Remove the `String.codepoints`
    shapes from it.
15. New `lib/pattern/no_codepoint_string_reverse.ex` handling **both `String.codepoints`
    shapes**; tag `[:single_codepoint_graphemes]`. Split the ported tests accordingly.
16. `test/pattern/no_codepoint_string_reverse_property_test.exs` — old vs `String.reverse`
    agree across the generator; **must include a `codepoints |> Enum.join` case** (the
    misroute guard from §4).
    - **Done when:** these tests green; the graphemes rule still fixes under `:strict`.

## Phase H — End-to-end + visibility (now real tagged rules exist)
17. `test/pattern/assumptions_filtering_test.exs` through the public API: default tagged rules
    run; `single_codepoint_graphemes: false` ⇒ no issue + `fix` untouched; `:strict` ⇒ only
    no-promise rules; `:default` under a `:strict` config re-enables; unknown user name raises;
    explicit-`rules:` filtered rule warns but stays filtered; `config :credence` respected and
    call overrides it; missing config is a no-op.
18. `rule_status/1` test: right on/off + missing-promise values under different options.

## Phase I — Meta-tests (the CI teeth)
19. Whole-suite: every rule's `assumptions/0` ⊆ `Assumptions.names()` (§11 rule-typo teeth).
20. Whole-suite: every rule with non-empty `assumptions/0` has a loadable
    `Credence.Pattern.<Rule>PropertyTest` in `test/pattern/<rule>_property_test.exs` (§18).

## Phase J — Changelog guard
21. CI step: if `@registry` defaults in `lib/assumptions.ex` changed in the commit and
    `CHANGELOG.md` did not, fail the build (§16 teeth).

## Phase K — Docs
22. `CONTEXT.md` and `docs/02_rule-review-process.md`: replace the old "identical output for
    every input" wording with the **reframed invariant** (`:strict` = zero promises =
    bit-identical; default = identical for every input the promises admit); add the
    shrink-first / reuse-smallest-promise / property-test / changelog notes and the
    "text-piece counts → character counts only behind `single_codepoint_graphemes`" line.
23. `README.md`: short section + the "this is about your *running data*" sentence + link to
    the `Credence.Assumptions` moduledoc.

## Phase L — Final check
24. `mix test` green; by hand confirm: default `fix` rewrites both example rules; `:strict`
    leaves them; `rule_status(assumptions: %{single_codepoint_graphemes: false})` shows both
    off with `single_codepoint_graphemes` as their missing promise. The property tests are the
    real proof of safety.
