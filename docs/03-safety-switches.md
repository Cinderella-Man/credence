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

## The rules of the system (decided)

- **Two modes, in plain words.** `:strict` = no promises, only always-safe rules, same
  result for every input. Default = the helpful set of promises is on.
- **A switch is the smallest, simplest promise** about the data that makes a rewrite safe,
  written as something you can actually check about your text. Switches are shared between
  rules. They are a flat list of independent on/off flags. We only add a new switch when a
  rule needs a promise that no existing switch already covers.
- **How many promises a rule needs:** none, one, or several. If it needs several, **all** of
  them must be on for the rule to run.
- **A rule must need the same promises every single time it changes code.** If one kind of
  change it makes needs a promise but another kind is always safe, **split it into two
  rules** — one always-safe, one that needs the promise. (We do exactly this with the
  string-reverse rule below.)
- **Defaults are chosen from what real data looks like, not from Elixir habit.** Elixir
  itself treats text as multi-piece characters by default; we deliberately do the opposite
  because our users' data is simple text. `single_codepoint_graphemes` is **on by default**.
- **The completeness promise (the heart of the safety story):**
  - If a rule needs a promise, then whenever that promise is true, the rule's rewrite must
    give the **exact same answer** as the original code — for every possible input that
    keeps the promise.
  - When any promise it needs is off, the rule must **not run at all**. That second half is
    what makes play-it-safe mode trustworthy: with every promise off, only always-safe rules
    remain.
  - **Shrink the rule first, lean on a promise second.** Before relying on a promise, narrow
    the rule so it only touches code where it is genuinely safe. A promise may only cover the
    leftover rare-text difference — never paper over a plain bug we could have caught by
    reading the code.
  - **Prove it with a property test.** Every rule that needs a promise comes with a test that
    throws thousands of random strings at both the old code and the fixed code and checks they
    always agree. (Details below.)
- **How you change the switches.** You pass `assumptions:` set to either a small map listing
  only the switches you want to change — like `%{single_codepoint_graphemes: false}` — or the
  single word `:strict`, meaning "turn every promise off".
- **Credence looks in three places, in order; the later one wins:**
  1. the built-in defaults,
  2. `config :credence` in the app's config,
  3. the options you pass straight into the function call.
  If a place isn't set, it's simply skipped — nothing breaks. Saying `:strict` in one place
  turns all promises off, but a later place can turn specific ones back on.
- **The switch filter always applies** — even if you hand Credence an explicit `rules:` list.
  One filter, one path, no surprises.
- **Asking what's on:** `Credence.Pattern.rule_status(opts)` returns a list describing
  **every** rule Credence found: its name, which promises it needs, whether it's on right
  now, and which needed promises are off. This is the place you look to see, at a glance,
  what you've promised and what that turned on or off. `enabled_rules/1` is just the names
  from that list where the rule is on.
- **When a switch name is wrong:**
  - **You** name a switch that doesn't exist (in the options you pass) → Credence **stops
    with a clear error**. You probably made a typo and want to know immediately.
  - A **rule** names a switch that doesn't exist → Credence turns that **whole rule off** (it
    won't run a rule whose promise it can't understand), writes a warning to the log, and the
    rule shows up in `rule_status` as off, with the bad name listed under its missing
    promises. A separate test that runs in CI checks that every rule only names real
    switches, so the typo is caught before release.
- **Not in scope:** `prompt.md` and the generator (a separate outside tool). We do **not**
  bring back the deleted charlist rules — those change a value's *type* (number ↔ string),
  which no promise can make safe.
- **Versions:** add a `CHANGELOG.md`. Because the helpful default can now change what
  Credence does, any new on-by-default switch, or any rule newly on by default, needs a
  changelog line — the default behaviour now depends on the version.
- **Where the docs live:** the real reference is the `@moduledoc` on `Credence.Assumptions`,
  right next to the list of switches so they're edited together and never drift. `ex_doc`
  renders it; the README links to it. No separate switches document beyond this plan and that
  moduledoc.

## What we build, file by file

- **`lib/pattern/rule.ex`** — add `@callback assumptions() :: [atom()]`. In `__using__`,
  give every rule a default `def assumptions, do: []` plus `defoverridable assumptions: 0`
  (same shape as `priority/0`). A rule that doesn't override it needs no promises and is
  never filtered out — so nothing that exists today changes.

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

## The two example rules we add

1. **`avoid_graphemes_enum_count_with_predicate`** — narrow both `check` and `fix` so they
   only touch a single-piece literal character (checked with
   `length(String.to_charlist(lit)) == 1`; verified to drop `""`, `"ab"`, and the
   two-piece form of `"é"`, and to keep `"a"`, `" "`, and the normal one-piece `"é"`). A
   shared `single_codepoint?/1` helper keeps `check` and `fix` in agreement. Tag it
   `def assumptions, do: [:single_codepoint_graphemes]`.

2. **`no_manual_string_reverse`** — **split it in two** (because its two changes don't need
   the same promise):
   - The **graphemes** version
     (`String.graphemes |> reverse |> join` / `iodata_to_binary` → `String.reverse`) stays an
     **always-safe rule that needs no promise** (verified the same for every input).
   - The **codepoints** version
     (`String.codepoints |> reverse |> IO.iodata_to_binary` → `String.reverse`) becomes a
     **new rule** that needs `[:single_codepoint_graphemes]` (verified: differs on the
     two-piece form, same on normal text; the result is still text → text). Name to be
     decided — e.g. `no_codepoint_string_reverse`.

Both come from the `evolution` branch (`/home/car/projects/credence_evolution`) together with
their tests.

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
character one single piece. The catch: the popular presets don't do this.

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
and the text still reaches past plain ASCII into `é ñ ü`. One definition, in `test/support`,
shared by every rule that needs this switch.

Plus a tiny **honesty check**: a test asserting that everything this generator produces really
is single-piece (every grapheme one codepoint). The character ranges are easy to fat-finger,
and this stops a broken generator from making all the safety proofs pass for nothing.

## Tests

- **`assumptions_test`** — the shape of `defaults/0`; `validate!` stops on an unknown name;
  `single_codepoint_graphemes` is on by default.
- **`assumptions_filtering_test`** (through the public API) — default: tagged rules run;
  `assumptions: %{single_codepoint_graphemes: false}`: no issue reported **and** `fix` leaves
  the code untouched; `:strict`: only no-promise rules run; a no-promise rule is unaffected;
  an unknown name you pass stops with an error; the `config :credence` place is respected and
  the call options can override it; a missing config place does nothing.
- **Whole-suite check** — every rule's `assumptions/0` only names real switches
  (`⊆ Assumptions.names()`).
- **Whole-suite check (the teeth on "every promised rule is proven)** — for every rule that
  names a switch, a property-test exists for it. We use a naming convention so this is
  checkable in CI: each such rule has a module like `Credence.Pattern.<Rule>PropertyTest` (in
  `test/pattern/<rule>_property_test.exs`), and a meta-test asserts that module loads for
  every rule with a non-empty `assumptions/0`. It can't judge whether the test is *good*, but
  it turns "tagged with a switch but never proven" into a **red build** instead of a silent
  hole — the same bar we set for the typo check above.
- **Per example rule** — the property test (StreamData, shared generator): old vs fixed agree
  across thousands of random single-piece strings; the two-piece / emoji cases are written
  down as known differences; the cases we shrank away are pinned as "no issue" at the default
  setting.
- **`rule_status/1`** — every rule listed with the right on/off and missing-promise values
  under different options.

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

## Decisions we already made (log)

1. Build the feature. 2. Defaults chosen from real data, not Elixir habit. 3. A switch is the
smallest shared promise about the data; flat list. 4. None / one / several promises, plus the
same-promises-every-time rule (split mixed rules). 5. A required old-vs-fixed property test.
6. StreamData (test-only dependency). 7. The value you pass is a small map **or** `:strict`.
8. Three places, in order (defaults < `config :credence` < call options); a missing place does
nothing. 9. The switch filter always applies, even to an explicit `rules:` list. 10.
`rule_status/1` lists every rule plus its missing promises. 11. A rule that names a missing
switch → the whole rule is turned off (not just the bad name dropped), shown as off in
`rule_status`, warned in the log, and caught by a CI test. 12. Narrowed to a single-piece
literal character (verified). 13. The generator / `prompt.md` are out of scope. 14. The
default helps most people, and we say so plainly — and we say the promise is about *running
data*, not source code. 15. No bringing back deleted rules here (type changes excluded). 16.
Add `CHANGELOG.md`, ship `0.7.0`. 17. Switch docs live in the `Credence.Assumptions`
`@moduledoc`. 18. Adopt examples #1 and #2 (the charlist rules stay rejected — they change a
value's type, which no promise can fix). 19. "Required property test" is enforced by a CI
meta-test (naming convention), not by trusting people to remember.
