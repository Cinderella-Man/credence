# 22 — The remaining work: single tracker for credence + harness

**Status:** ACTIVE — this is the only file that tracks open work · **Adopted:** 2026-07-28
**Owner:** maintainer + Claude sessions

**The rule of this file:** when an item lands, edit it *here* (strike it, add the
commit id). No other document tracks progress any more — docs/12/13/16/17/19/20
and the harness's `IMPROVEMENTS.md` are the *specs and history* this file points
into; they carry banners saying so. Work-in-progress (started but uncommitted)
goes in `docs/21-in-flight.md`; everything else lives here.

Every claim below was produced by a 6-agent read-only research pass on
2026-07-28 (4 miners + 2 adversarial verifiers, all claims re-derived
independently; corrections already folded in). File:line anchors were verified
against `credence` HEAD `958f241` and harness HEAD `fb3bc2a`.

**Second pass, same day (through `f521138`).** T0.1, T0.2, T1, T1.3, T3.1, T3.2
and T3.7 landed, plus a new gate (the self-corruption oracle) and the first three
rules of the T3.10 ledger it opened. **Six** of this file's own claims were
**refuted by execution** and are corrected in place, each marked *Correction* at
its item:

1. T3.1's "7 dead rules" — really 1.
2. T3.2's "will be dropped" — already being dropped, and 3 outcomes not 1.
3. docs/16's `SourceMask` repair claim — never made; became T3.7.
4. T1's implied scope — the 86 are Semantic/Syntax only; Pattern is 155/155 clean.
5. T3.7's own defect scope — 1 shape recorded, 6 live.
6. T3.10's own paydown ordering — line count is not a severity proxy for a rule
   that *changes* line count, which put `no_else_if` at the top of the queue for
   the wrong reason (T3.10a).

The pattern worth keeping: **every one of these was a plausible written claim
that nobody had run.** Where a claim here is not marked as executed, treat it as
a hypothesis.

T3.7 sharpens that into a rule of thumb. Its item was *itself* the correction of
an earlier unexecuted claim — and it was still wrong, in the same direction,
because the correction had also been written from reading. **An unexecuted
correction is not more reliable than the unexecuted claim it replaces.**

And T3.10 sharpens it once more, in the direction that actually pays: what broke
the loop was **changing the input, not the effort**. Reading a fix and reading
its tests is one act, not two — the same person wrote both, so they agree by
construction. An input nobody authored breaks the tie, and a Syntax rule's own
source file is one, for free.

---

## Status at a glance

Completed items are **struck through** in the tiers below and carry their commit
id in place. 🔄 marks the one item in progress; everything not listed here is
untouched.

| | Item | Commit |
|---|---|---|
| ✅ | T0.1 — push both repos | `917557c` (C) · `7b6e2c6` (H) |
| ✅ | T0.3 — zero-warning compile | earlier session |
| ✅ | **T1 — the pipeline-witness gate** (the file's top item) | `2f34640` |
| ✅ | T1.3 — the C2.2 vacuity block | `070f090` |
| ✅ | T3.1 — errors on compiling source, + the inert C4 gate behind them | `c691362` |
| ✅ | T3.2 — the `:no_op` trace outcome, both repos | `7708aef` · `7b6e2c6` |
| ✅ | T3.9 — tree-wide formatter drift (57 files) | `f564e31` |
| ✅ | T0.4 — release hygiene (fold 0.7.0, fix a false fix-note) | `24ce7df` |
| ✅ | T0.2 — Phase-4 PR | `1cb7bff` — **superseded**, a PR for the whole 3rd evolution already exists |
| ✅ | **T3.7 — the last two raw-byte syntax fixes**, + the `FixDivRem` half-conversion behind them | `e81985e` · `8169601` |
| ✅ | **the self-corruption oracle** — a new gate, and the 11 rules it found | `b41af7b` |
| ✅ | **T3.10 — pay down the self-corruption ledger** — 10 of 11 done; the only entry left is the deliberate one | `becd59b` · `643435a` · `e549bd0` · `a9ad691` |
| ✅ | **T3.10a — `no_else_if` corrupts valid parsing code** — all four steps done; the rule is **retired** into its widened sibling and the self-corruption ledger is **EMPTY** | `f23722f` · `4e9d16d` |
| ✅ | **T3.8 — the two rules T1 proved cannot fire** — both alive: one re-homed, one re-keyed | `e549bd0` · `3cdbe14` |
| ✅ | **T5.9 — the T1 witness ledger is EMPTY** — all 8 paid down; every rule witnesses (290/290 as measured then; the live count is **289** since `no_else_if` was retired — the gate derives it at runtime, so only the written figure aged) | `f895bee` · `f32e315` · `6d72130` |
| ✅ | **T5.10 — the AST differ patches a bare list one column inside its `[`** — fixed at the wrapper, and the helper has a test at last | `8b870b5` |
| ✅ | **T3.11 / T5.6 — `compile_and_capture/1` executes what it analyses, unbounded** — the seven OOM kills of 2026-07-28, diagnosed and fixed; also closes C6's second half | `1ddbfe6` |
| ✅ | **T1.2 — the dispatch-simulation gate** — every contended pair was ordered correctly *by accident*; two priorities now say so | `aea4f7c` |
| ✅ | **T2.1 [H] — Gate corpus dispatch**, plus the anchors probe that had never been run | `11a3d0e` |
| ✅ | **T2.2 [H] — H8 verdict memory + rejected-mechanism exemplars**, all six controls re-run red | `be31904` |
| ✅ | **T4.1 [H] — the STATUS.md interlock**, which until now described itself | `24f2dee` |
| ⬜ | everything else | see the tiers below — **Tiers 0 and 1 are closed** |

**Where to start: `STATUS.md`.** As of 2026-08-16 it carries the ordered
release map — what is left to merge, cut 0.8.1, and stand up Phase 9 — grouped
A–F and stripped of everything already done. This file stays the item-level
record: the evidence, the corrections, and the reasoning behind each task. When
the two disagree about whether something is done, believe the code and fix both.

Tiers 0 and 1 are closed (T1, T1.2, T1.3 all landed), as is the whole
self-corruption line (T3.7 → T3.10 → T3.10a): its ledger is empty and the gate
that measured it was rebuilt so that being empty does not make it vacuous. Tier
2 is closed except **T2.3**. The harness half of T1 — defined at this file's own
T4.1–T4.3 — is done except **T4.2 (c) and (d)**, which are the minimum in-loop
gates still owed before a Phase-9 run.

---

## Part I — The evaluation: what the evolution actually taught us

### 1. The headline numbers

The evolution run committed ~259 rule bases, **each of which passed the
harness's own Gate**: the full credence suite, the corpus scan, the mutation
check, the equivalence probe. At acceptance review:

- **116 survived (45%). 143 were rejected (55%).**
- Of the 143: 82 implementation-dead · 25 duplicates of live rules · 9 false
  premises · 17 rebuild-later · 9 salvage-small-fix · 1 already-live
  (`docs/18-per-rule-verdicts.json`, the source of truth).
- **135 of the 143 encode a real failure mode.** The rules were wrong; the
  *observations* behind them were mostly right. 56 of those failure modes are
  caught by nothing in Credence today (mode-level count, docs/18 §5).
- Of the **116 accepted**, seven rules later turned out to carry **nine live
  shipped defects** (docs/16 §4.6a) — every one repaired since, but every one
  survived both the harness Gate *and* first-pass human review.
- 43 of 143 verdicts were **overturned on adversarial re-review** — first
  readings of a rule are wrong at ~30% even for careful reviewers. Machinery,
  not vigilance, is what scales.

### 2. Why 55% died: the gate-gap tally

Every rejected rule was assigned the earliest, cheapest *mechanical* check that
would have killed it at generation time (full per-rule lists preserved in the
research scratchpad; counts adversarially re-verified on a 24-record sample,
21/24 concordant, corrections folded in):

| Gate that was missing | Rules | Share |
|---|---|---|
| **G1** — diagnostic-reachability: the semantic rule keys on a compiler message the compiler never emits for its target, or one the pipeline drops | **35** | 24.5% |
| **G2** — phase-reachability: the syntax rule's target *parses*, and `lib/syntax` only runs on parse failure | **18** | 12.6% |
| **G3** — dispatch-slot ownership: a live rule already matches the diagnostic; `Enum.find` first-match-wins means the newcomer is dead on arrival (or steals a slot and no-ops) | **33** | 23.1% |
| **G4** — execution-verified fix: the fix no-ops, corrupts neighbours, or leaves the diagnostic unresolved — visible only by *running* it | **26** | 18.2% |
| **G5** — duplicate-of-live: same failure mode as an existing rule (five were literal same-name copies) | **20** | 14.0% |
| **G6** — premise-false: the rule is wrong *about Elixir*; only an executed language probe catches it | **9** | 6.3% |
| **G7** — corpus over-fire | **0** | — |
| **G8** — human judgment only | **2** | 1.4% |

**The three headline conclusions:**

1. **86 of 143 (60%) died for one architectural reason: the rule never actually
   runs in the real pipeline** — and the Gate never noticed because the rules'
   green tests "pass only by calling `analyze`/`fix` directly, bypassing the
   phase" (docs/17:426). A fabricated diagnostic appears in three
   mutually-consistent files (rule `@match_msg`, check test, fix test), so the
   rule agrees with itself and ships dead. **One end-to-end gate kills all 86**:
   *the rule's own bad fixture must produce this rule's issue AND a changed fix
   through the top-level `Credence.analyze`/`Credence.fix` entrypoints,
   dispatched against the full live rule set.* (Per-sub-gate checks are weaker:
   a borrowed-but-real diagnostic passes a match?-reachability check and dies
   only end-to-end — verified on `fix_regex_in_guard`.) This is **T1** below.
2. **G7 = 0 is a success story, read correctly.** The corpus gate existed for
   the Pattern phase — and only 4 of 143 rejects were Pattern rules. Where a
   real oracle existed, the failure class *vanished from the reject pile*.
   Over-fire migrated to exactly the phases with no oracle (semantic matchers,
   syntax regex fixes). Build the oracle, kill the class.

   *Instance, `b41af7b`:* the byte-scope class had two oracles — corpus
   fix-safety and fix-output re-parse — and **neither can see it**, because a
   corrupted string literal still parses, still compiles, and still satisfies
   every assertion in the rule's own fix tests. So the class was gated only by
   review, and review missed it four times. The oracle that does see it costs one
   `fix/1` call per rule: **run the rule over its own source file.** It found 11
   of 45 Syntax rules on the first run, including one already reviewed,
   converted, tested, changelogged and shipped as fixed. The transferable shape
   is not "test your rules on their own source" — it is *find an input the
   author did not choose*. Fixtures and rule share an author and therefore share
   a blind spot; a rule's own file is adversarial for free.
3. **132 of 143 (92%) were mechanically catchable.** Only G6+G8 (11 rules)
   genuinely needed judgment or a bespoke language probe. The review burden that
   consumed a week of drain time was, to 92%, automatable *before commit*.

### 3. Why the 9 accepted-side defects escaped

They cluster in exactly the two dimensions the Gate did not measure:

- **Byte-level scope of the edit** (5 of 9): rewriting inside string literals,
  swallowing a `def` head, reading `%Name{}` as modulo. Fixed since by
  `Credence.SourceMask` + fix-output re-parse. The gate lesson: *a fix's blast
  radius needs its own oracle* — corpus fix-safety and re-parse checks, which
  now exist.
- **Meaning of the output** (4 of 9): output compiles clean and returns a
  different answer (`a * b % 2` regrouped; early-`return` branch deleted;
  `h * 31 + c & 0xFFFFFFFF` → 4294967306356 instead of 10356). Two shipped
  fix-tests *asserted the bug as expected output*. Fixed since by
  `Credence.RuleCase.call_fixed/4` and the C2.2 dimension gate. The gate
  lesson: **green tests are not evidence; compiles-clean is not correct** —
  only executed meaning is.

### 4. What this means for weak models (MiMo/Xiaomi)

The generating model does not need to get smarter — the loop needs to stop
accepting unwitnessed claims. Every principle below is derived from the tally:

1. **Ground generation in executed reality, don't just gate it afterwards.**
   The single biggest class (G1, fabricated diagnostics) exists because the
   model was asked to *imagine* a compiler message. The harness already
   captures the real diagnostic and hands it to the model verbatim
   (`seed.ex:169-186` — this is why the class shrank in later passes); what
   remains is fixing the lossy channel it reads from (T-H2 below) and making
   the same grounding mandatory for the bugfix lane (evidence extraction, not
   the classifier's hand-reduced repro — three live over-fires were talked
   away exactly there, ledger rows 40/50/59).
2. **Reachability is provable at authoring time, cheaply.** Syntax: one
   `Code.string_to_quoted/1` call proves the fixture doesn't parse (G2, 18
   rules, a one-liner). Semantic: compile the fixture, require the captured
   diagnostic to reach the rule through real dispatch (G1+G3). The weak model
   never needs to *understand* phase semantics if the gate simply refuses
   unwitnessed rules — with a failure message that names the one repair action.
   Every gate in this codebase already follows that message discipline; keep it.
3. **One diagnostic, one owner — checked by simulation, not policy prose.**
   docs/20 states the policy; nothing enforces it (G3, 33 rules). Simulating
   dispatch over the live rule set is mechanical (T2/T1).
4. **Dedup at proposal time, with mechanisms not names.** 20 rules were
   re-inventions; the dispatch design itself *caused* churn (a landed rule
   silently killed a proposal, so the model wrote it again under a new name).
   H8's verdict memory + the rejected-mechanism list (already built in salvage,
   R1–R7, teaching by example) is the counter. A list of rule *names* teaches
   nothing — the next proposal has a different name.
5. **Ratchets, not walls.** C13/C14 proved the shape: freeze today's debt in a
   ledger that only shrinks, gate the *delta*. A weak model can't make the
   audit worse, and nobody faces a 40-red-rules wall that teaches them to
   disable the gate.
6. **Route work by oracle strength.** Pattern has corpus + equivalence +
   fix-safety oracles; Semantic has the compiler; Syntax has the parser. The
   phases are not equally safe for weak models — pattern-phase proposals get
   the most machine verification per token. Prefer steering cheap models there;
   require the grounding artifacts (captured diagnostic / parse-failure proof)
   before an expensive implementer session is ever spawned. The premise-check
   is ~one compile; ledger estimates ~$100 of implementer budget wasted across
   just nine reviewed rows for want of it.

---

## Part II — The task list

Ordered by tier. Within a tier, top-to-bottom is the recommended order.
Conventions: **[C]** = credence repo, **[H]** = harness repo. Every task names
its evidence and its acceptance bar. Gates ship with positive controls seen red
on purpose — no exceptions; a gate nobody has seen red is unverified.

### Tier 0 — hygiene (minutes each; do before anything else)

- [x] ~~**T0.1 [C][H] Push.**~~ DONE 2026-07-28. credence through `a590f07`, harness
  through `c2b0d95`. (This session's later commits are listed in Part III.)
- [x] ~~**T0.2 [C] Open the Phase-4 PR.**~~ **NOT NEEDED — superseded.** The
  maintainer already has a PR open covering the whole third evolution, so a
  separate Phase-4 PR is redundant. `docs/PR_BODY_phase4.md` stays as provenance
  and is now factually accurate (its overstated `SourceMask` scope was corrected
  when this was still live); reuse it as review notes if useful.

- [x] ~~**T0.3 [C] Zero-warning compile.**~~ DONE this session: the provably-dead
  `extract_atom/1` clause (`lib/pattern/no_keyword_get_keyword_key.ex`) is
  deleted; `mix compile --force` = 0 warnings.
- [x] ~~**T0.4 [C] Release hygiene.**~~ **DONE.** Two `Unreleased` headings is
  not a valid changelog state, and there are **zero git tags** — neither 0.7.0
  nor 0.8.1 was ever cut, while `mix.exs` already reads `0.8.1`. So 0.7.0 is
  folded into 0.8.1 (the option this item listed), leaving one section, still
  `Unreleased` because stamping a date is the release act and that is yours.
  0.8.1 also had **two separate `### Added` blocks**; merged. Final order is
  Keep-a-Changelog's: Added, Changed, Fixed. Verified content-preserving — 22
  bullets before and after, and a blank-and-header-stripped diff shows only the
  section reorder plus the correction below.

  **The correction matters more than the tidying.** The Fixed entry claimed
  "**All four** now match against a `Credence.SourceMask` shadow". Only two do.
  That is the T3.7 defect, restated in the one file that ships to users — so
  0.8.1 would have released a fix note for a fix that does not exist. Now names
  `FixPythonModulo` and `FixDivRem` as converted and states plainly that
  `FixPythonFloorDiv` and `FixScientificNotation` are not.

### Tier 1 — the reality gates (kills the 60% class at birth)

- [x] ~~**T1 [C] The pipeline-witness gate — every rule must witness its own
  failure mode through the real pipeline.**~~ **DONE `2f34640`** — see the
  result box immediately after this item. One new meta-test
  (`test/pipeline_witness_test.exs` + `test/support/pipeline_witness.ex`)
  asserting, for **every** rule in all three phases: feeding the rule's own
  bad fixture to the top-level entrypoints (`Credence.analyze/2`,
  `Credence.fix/2` — full live rule set, real dispatch, real
  `compile_and_capture`) yields (a) an issue attributed to *this* rule, and
  (b) for fixing rules, output ≠ input with the triggering condition resolved
  (diagnostic gone / now parses). This subsumes three sub-gates and would have
  killed **86 of the 143** rejects (G1 fabricated/borrowed diagnostics 35, G2
  wrong-phase 18, G3 dispatch losers 33):
  - *Semantic reality:* today `semantic_meta_test.exs` is shape-only — a
    hand-fabricated `%{severity:, message:}` map passes every check; only 10
    of 90 semantic rules voluntarily use `compile_and_capture` in tests.
  - *Syntax reality:* `syntax_meta_test.exs` pins that fix **output** parses
    but never that the check fixture **input** fails to parse — the entire
    docs/17 "inert by construction" class is unguarded. Only 4 of 87 syntax
    test files assert input-unparseability. (Per the repo's own test-hygiene
    gate, the assertion belongs behind a `RuleCase` verb, not raw
    `Code.string_to_quoted` in test files — `no_parser_calls_in_rule_tests`.)
  - *Dispatch reality:* running through real dispatch proves the rule *wins*
    its slot — a rule shadowed by an earlier-sorting live rule fails here.
  Mechanics: fixtures are enumerable via `Credence.MetaTestSupport.fixtures/1`
  (the C7 salvage already extracted 5,144 of them); reuse
  `RuleHelpers.compile_and_capture/1` (`lib/rule_helpers.ex:160`) and
  `RuleCase.call_fixed/4`. Expect a ledger: some live rules will fail this
  gate honestly (see T3.1 — at least 7 semantic rules are dead in production
  right now); freeze them C13/C14-style, ratchet down. Positive controls: a
  fabricated-diagnostic fixture rule, a parses-fine syntax fixture rule, a
  shadowed semantic rule — each seen red. **Harness half:** the same witness
  requirement goes in the Gate (cheap pre-check before the suite phases) and
  the seed (teach it; today the model learns it only by failing).
  **RESULT (2026-07-28, `2f34640`). 280 of 290 rules witness.** Pattern is
  **155/155** — which is itself the finding that the 86 were never a Pattern
  problem; the whole class lives in Semantic and Syntax. Syntax 44/45, Semantic
  81/90. Two **live shipped rules cannot fire at all**, one from each historical
  class, now tracked as T3.8:

    * `Syntax.FixMalformedSpec` (G2, wrong phase) — its moduledoc says
      "## Bad (won't parse)" but `@spec save!(map() :: {:ok, map()})` *parses*:
      `::` is an ordinary right-associative binary operator
      (`elixir_parser.yrl`, `Right 60 type_op_eol`), so `f(a :: b)` is a
      well-formed call argument. Inert by construction.
    * `Semantic.FixWithElseBareValue` (G1, unreachable diagnostic) — `match?/1`
      requires a message Elixir 1.20.2 does not emit.

  The remaining 8 were ledgered **with a reason**, because the reasons demand
  different repairs: 4 `:dep_gated` (plug/nimble_csv absent here, present in the
  harness workspace — these rules are alive there), 2 `:no_fixture`, 2
  `:wrong_phase`. Paydown was **T5.9**, and it is complete: **the ledger is now
  empty and 290 of 290 rules witness.** Every one of the four reasons turned out
  to name a different defect and none of them meant "this rule is fine" — one was
  a property of this checkout, one was a rule keyed to two disjoint situations,
  one was a rule in the wrong phase twice over, and one was a rule that had never
  fired at all.

  Two probe bugs were found and fixed *before* trusting any of it, both of which
  had manufactured false accusations against live rules — recorded because the
  lesson generalises to every gate of this kind: (1) Sourceror returns a literal
  as written in the file, escapes intact, so every fixture containing `\\`
  failed the parse filter and condemned both default-args rules; (2) the
  candidate pre-filter demanded a keyword or bracket and dropped `"x = 1e-10"`,
  the entire fixture set of `FixScientificNotation`. **A pre-filter in front of a
  correctness gate must never be cleverer than the gate.** Fixing both moved 3
  rules from unwitnessed to witnessed.

  Runtime 202 s -> 3.7 s via two exact identities, each pinned by its own test:
  for candidates filtered by parseability, a phase's `analyze/2` equals
  `Credence.analyze/2`; and Pattern/Syntax concatenate without contention, so a
  single-rule probe is exact there. **Semantic is never narrowed** — that would
  hand every rule an uncontested slot and delete the G3 class. Most of the rest
  was an accidental quadratic (155 rules x 472 files = 73,000 re-parses).

- [x] ~~**T3.11 [C] `compile_and_capture/1` executes what it analyses, with no
  bound.**~~ **DONE `1ddbfe6`.** `Code.compile_string/2` evaluates top-level
  expressions, so analysing source runs it — on the live pipeline
  (`lib/semantic.ex:134`, `:190`, `:393`), not only in the gates. Verified by
  handing it a `File.write!/2` and finding the file. The input that mattered was
  already in the tree: `Enum.flat_map(1..10, &Stream.cycle([&1]))`, the *expected
  output* of an `UndefinedFunction` fix test, harvested as a witness candidate.
  It materialises an infinite stream — one fixture, 200 MB → 3.6 GB in 8 s, and
  it was the direct cause of **seven kernel OOM kills on 2026-07-28**, each a
  `beam.smp` at 60–63 GB. Now bounded by a 512 MB heap ceiling and a 30 s
  deadline in a monitored child; aborts return `{:error, [diagnostic]}` so
  `compiles?/1` says false. Controls: each bound perturbed to a value nothing
  compiles under. Full incident, timings and the two methodological findings are
  in docs/21's final section — including that **the suite was never the cause**
  (1.2 GB peak) and that the agent-concurrency rule adopted after the first crash
  was followed faithfully while six more kills happened under it.

- [x] ~~**T1.2 [C] Dispatch-simulation gate (the G3 residue T1 doesn't cover).**~~
  **DONE `aea4f7c`** — `test/dispatch_contention_test.exs` +
  `test/support/dispatch_contention.ex`. Compiles every Semantic rule's own
  witness fixtures, captures the real diagnostics, and asks which live rules
  claim each. Where more than one does, the winner must have a **strictly lower
  declared priority**; a tie means the alphabetical tiebreak in
  `Enum.sort_by(&{&1.priority(), &1})` is load-bearing, which docs/20 §2
  forbids.

  **The finding: every contended pair was ordered correctly, and none of it was
  chosen.** Fifteen-odd specific rules beat the `UndefinedFunction` catch-all
  only because their module names sort before `U`. Renaming any one of them past
  `U` would have handed its diagnostic to the catch-all — and in Semantic that
  is not a delay, it is a replacement: a structural repair (restructuring an
  early-exit block, emitting `@on_load`) becomes a renamed call, silently, with
  the suite green.

  **The repair was two priorities, not fifteen.** The relationship is one claim —
  *the general rule yields to the specific one* — so it belongs on the general
  rule: `UndefinedFunction` and `NoUnreachableCaseClauseByType` declare **501**
  (docs/20 §4's "runs after the default population"). Fifteen copies of the same
  assertion would have been fifteen things to keep in sync.

  Note this is deliberately **not** docs/20 §3's "narrow one `match?/1`". §3
  addresses a loser that is wholly dead; `UndefinedFunction` still owns every
  other `undefined function` message and is shadowed only on the spellings a
  specific rule claims. Narrowing it would mean teaching the catch-all the names
  of its fifteen exceptions.

  Ledgered, C13/C14-style: 9 pairs win on a declared priority without naming the
  rule they beat (docs/20 §1). The list may only shrink — a separate test fails
  on a *stale* entry, so paying one down forces its removal.

  **Correction (2026-08-16): none of the 9 has been paid down.** This paragraph
  used to close "One was paid down in this pass"; the ledger in
  `dispatch_contention_test.exs:27-37` still holds all nine. The T1.2 repair was
  the two *priorities* on the general rules, which is a different debt from this
  one — that fixed the ordering, this records that a winner does not say why it
  wins. Tracked as an open item in `STATUS.md` (D12); eight of the nine beat
  `UndefinedFunction`, so it is one sentence per winning moduledoc.

  Controls: the machinery takes its rule list as an argument, so it is exercised
  against fabricated rules — two claimants detected, one claimant not reported,
  a raising `match?/1` counted as a decline — plus population floors on the
  captured diagnostics and the live rule set, because both assertions would pass
  over an empty set and say nothing. That is the T3.10a lesson applied at
  construction rather than after the ledger empties. The live gate was also seen
  red on real offenders before the fix.
- [x] ~~**T1.3 [C] C2.2 population guard.**~~ **DONE `070f090`.** Added the full
  `describe "the gate cannot pass vacuously"` block in the C13/C14 idiom rather
  than the single `assert judged != []`: the real hazard is that the trigger
  (`rule_stdlib_callees/1`, a regex over whitespace-stripped rule source) stops
  matching, which zeroes both class populations while `judgeable` stays healthy.
  Pins the analysed set (155), the judgeable set (134) and each class's subject
  set (10 and 10). Control: collapsing `@scanned_mods` turns the new guard red
  while gates 1 and 2 stay GREEN — that green *is* the vacuity.

### Tier 2 — land the salvage (near-done, verified work sitting in a directory)

Order per the salvage assessment (dependency- and completeness-driven). All in
`/home/kamil/projects/credence-salvage-2026-07-28/`; every item's remaining
verification is listed in `docs/21`. Treat every artifact as unverified until
its own tests run under real `mix test`.

- [x] ~~**T2.1 [H] Gate corpus dispatch (Addendum 2 / Phase 8.7)**~~ **DONE `11a3d0e`** — was ~90% done in
  `b2-gatedispatch/`. `Cev.Evolve.CorpusDispatch` plans `{:skip|:scoped|:full}`
  from staged paths; scoped scan is a **fail-fast pre-gate, never a
  substitute** (scope-parity is NOT answered by a clean `--only-rule` scan —
  measured with a planted leaky rule: 0 over-fire findings vs 12 scope-parity
  violations). 29/29 unit tests, 9/9 mutants killed, 6/6 integration tests,
  positive control = suite red under unpatched gate. It does **not** touch
  classify/prompt (collision map corrected). Remaining: finish the
  anchors-vs-`credence.corpus.ex` probe (RESULT lines already verified),
  real `mix test`, formatter. Data point worth keeping: 150 of 155 committed
  candidates were syntax/semantic-only — this saves ~234 s × most rows.
- [x] ~~**T2.2 [H] H8 verdict memory + rejected-mechanism exemplars**~~ **DONE `be31904`** — was ~95%
  done in `b2-h8/`. `Cev.Classify.Verdicts` (cache-scoped, hash-keyed,
  advisory-only), R1–R7 mechanism list (each led by MECHANISM, rule name only
  as provenance — the ledger's hard requirement), three worked exemplars
  probed against the live pipeline. 42/42 tests + six positive controls all
  seen red. Remaining: place files, real `mix test`, format.
- [ ] **T2.3 [H] LD3+LD4 merge** — ~60% done in `b2-ld34/`. Four modules with
  measured moduledocs; empirically validated against all six real
  `:no_lib_change` rows (rows 40/50/59/123/145 → `:contradicted`; only row
  178 genuinely `:refuted`). **Zero tests exist** (killed at "Now the
  tests."), and the Gate/Router integration was never designed: live
  `gate.ex:198-202` (`check_touches`, reached from the with-clause at
  `gate.ex:128`; `:116` is now `@suite_retries`) rejects with a bare
  `:no_lib_change` atom and discards the
  tree; `TestOnlyDiff.adjudicate/4` needs `{:no_lib_change, %{entries, patch}}`
  captured before discard, then Router → adjudicate → persist →
  `VerifiedGood.record` → `RowLog.verified_good`. Merge note: H8 and LD34
  overlap in `classify.ex run/3` and `prompt.ex build/1` (~3 lines apart) —
  take H8 as base, add LD34's one keyword + block; mechanical. Honesty note
  from the salvage itself: LD4's register is a **one-rule** register on this
  run's data — what stops the NoPythonMultiReturn churn is the
  repro-validation gate (T4.2), not LD4. Also: `trace_evidence.ex`'s
  `changed_blocks/2` fix was never re-probed (formatting-only risk), and
  `:refuted` is Semantic-only until T3.2 lands.
- [x] ~~**T2.4 [C] C18 mutant sweep**~~ **DONE `b1297c7`.** Placed, tested, and
  **re-measured on a quiet box** — which is what this item was waiting for, since
  the salvaged numbers came from a 20-parallel run while the machine was OOMing.

  | metric | value |
  |---|---|
  | rules swept (sample 39, seed 0) | **39** |
  | corpus kill rate | **0.740** |
  | killed / survived | 629 / 221 |
  | timeout / invalid / error | 0 / 2 / 0 |
  | wall clock | 189 s, peak 2.6 GB |

  `no_manual_max` reproduces the salvage's **0.848** exactly, so the engine is
  deterministic across machines and runs. Report-only stays report-only: no
  `--fail-under`, not wired into the suite, per docs/12 C18 + E6 — the tail has
  not been triaged yet and a floor set before that would be a number nobody can
  defend.

  Controls, all three docs/22 asked for: a **planted misaligned mutant** must
  raise rather than corrupt a different token (the whole measurement assumes the
  edit lands where the tokenizer said, and a silent miss would move every score
  with nothing to notice it); a mutant pointing past the end of source likewise;
  and a **red baseline is discarded, not scored** — a triplet that was already
  failing kills every mutant and scores a perfect 1.0, which is the single most
  misleading number this task could print. Plus the exclusions that keep the tail
  honest (moduledoc, comments, string contents) and `kill_rate/1` returning `nil`
  rather than 0.0 when nothing scorable ran.

  Original: ~70% done in `b2-c18/`.
  `Credence.Mutation` (4 operator families, careful scoping, cap-40
  round-robin), `Sweep` (fresh BEAM per mutant, mandatory green baseline —
  "a red baseline kills every mutant for the wrong reason"), `mix
  credence.mutants` (report-only **on purpose**; no floor until the tail is
  triaged, per docs/12 C18 + E6). End-to-end smoke-proven: `no_manual_max`
  kill rate 0.848 and its survivors reproduce docs/14 E6's known equivalent
  mutants exactly. Remaining: ExUnit tests + positive controls (planted
  always-true matcher; `apply_mutant` misalignment raise; baseline-red
  discard), placement, and **re-run the 39-rule sample on a quiet box** —
  the salvaged kill rates came from a 20-parallel run while the box was
  OOMing; do not publish them.
- [x] ~~**T2.5 [C] C7 idempotency gate.**~~ **DONE `8f400fd`** — the checkbox
  trailed the work by three weeks; the body below has said DONE since the gate
  landed. Verified 2026-08-16 by running it: the always-on half is green and the
  full `--only idempotency` sweep passes (650 s on a quiet box, against a
  `timeout: 900_000` — thin headroom, so run it quiet).
  The measurement the salvage died before producing (it stopped at ~750/5,144)
  now exists, re-extracted and re-run twice:

  | | |
  |---|---|
  | fixtures swept (unique, 290 files) | **5,188** |
  | `fix/1` raised | **0** |
  | changed by pass 1 | **2,158** |
  | **non-idempotent** | **29** (1.3% of changed) |

  That corroborates docs/14 E7's ~1.5% estimate from an independent direction.
  It was 31 before T3.12 below, which the sweep found.

  **The decision this item asked for: a pinned ledger, not an assertion.** Most
  of the 29 are *cascades by design* — 13 are a Pattern fix leaving a variable
  the Semantic round then reports as unused, which is E7's "one Semantic re-pass
  after Pattern changes" happening exactly as intended. A flat "fix/1 must be
  idempotent" assertion would be red for correct behaviour and would teach
  people to disable it. The C13/C14 ratchet shape fits: freeze the 29, gate the
  delta, and require a new entry to be argued for.

  **DONE `8f400fd` — the gate is built.** `test/idempotency_test.exs` +
  `test/support/idempotency.ex`, in two halves:

  * **always on, 4 s** — the 29 ledgered fixtures must still be non-idempotent.
    Pay one down and this goes red until the row is deleted, so the ledger cannot
    rot into permission for a regression.
  * **tagged `:idempotency`, ~8.5 min, excluded by default** — no fixture
    *outside* the ledger may be non-idempotent. `MIX_ENV=test mix test --only
    idempotency`.

  Plus machinery controls that hold whether or not the ledger is empty (the
  T3.10a lesson applied at construction) and a population floor on extraction.

  **The gate immediately disagreed with the sweep that seeded it, and the gate
  was right.** It flagged a 30th fixture — and run *alone*, that fixture is a
  fixpoint. The difference is the **host VM**: `fix/1` compiles what it analyses,
  and a Semantic rule keying on "module is not available" stops firing once an
  earlier fixture has defined that module. So the original sweep's 29 was partly
  a record of the order fixtures happened to run in.

  Fixed in the detector rather than absorbed into the ledger: every module the
  source defines is purged before each pass, so the answer depends only on the
  bytes. With that, the full sweep agrees with the ledger exactly — 0 failures.
  **A fixpoint measurement taken in a warm VM is measuring the VM.**
- [x] ~~**T3.12 [C] `UsedUnderscoreVariable` renames variables into aliases.**~~
  **DONE `7f3804a`** — found by the T2.5 sweep, which is the argument for having
  run it. `fix/1` stripped exactly **one** leading underscore with no check that
  the result was still a variable, so:

      __MODULE  -> _MODULE  -> MODULE      (one underscore per pass)

  and `MODULE` is an **alias**. `MODULE = :mod` compiles clean and raises
  `MatchError` at *runtime* — docs/22 §3's "output compiles clean and returns a
  different answer", the worst shape a fix can have, and invisible to every gate
  that checks parseability or compilation. Two more shapes fell out of the same
  missing check: `__foo` → `_foo` re-fired forever (the walk that reached the
  alias), and `_` → `""` spliced an empty name over every `_` in the clause.

  Now strips *every* leading underscore and declines unless the result matches
  `^[a-z][A-Za-z0-9_]*$`. Declining is always safe here — the diagnostic is a
  naming-convention warning, so leaving it costs a lint message while renaming
  to a non-variable costs the program. Controls: all four shapes pinned, plus
  GREEN-0 on the ordinary rename.

### Tier 3 — live defects on the branch (the ledger's FIX-CREDENCE rows)

- [x] ~~**T3.1 [C] Type-checker diagnostics are dropped.**~~ **DONE `c691362`.**
  Mechanism confirmed by execution on Elixir 1.20.2: `%S{unknown: k}` in a case
  clause or a function head yields `unknown key :unknown for struct S` at
  `severity: :error` **on the `{:ok, …}` branch**, and `Semantic.analyze/2`
  returned `[]` for it. Fixed by `@compiling_severities` in `lib/semantic.ex`.

  **Correction to this item's own claim.** It said "7 live semantic rules are
  dead in production". The real count is **one**:
  `FixJasonDecodeErrorMessageField`. Elixir raises a checker diagnostic to
  `:error` in exactly two places, both struct checks in *pattern* position
  (`Module.Types.Of` via `Module.Types.Pattern`); the same checks in expression
  position stay `:warning`. So the colon-vs-dot spelling is the discriminator —
  `unknown key :k for struct M` (pattern, error) vs `unknown key .k in
  expression:` (expr, warning) — and exactly one live rule keys on the former.
  The five rules keying on the latter were never affected. The "7" was
  unverified and is now refuted.

  **The larger find was a second, independent hole.** `health_from/2`'s
  `{:ok, …}` clause hardcoded `errors: %{}` and discarded its diagnostics
  argument, so `verdict/2` could only ever return `:ok` on that branch: the
  **entire C4 revert gate was inert for the warning pass**. Widening `analyze`
  without it would have shipped a wider fix path with no gate behind it.

  **Deliberately not done:** the `docs/18:1312` variant, which reclassifies an
  `{:ok, …}` carrying any `:error` as `{:error, …}` inside
  `compile_and_capture/1`. That flips `compiles?/1`, and `pattern.ex:79` skips
  the *entire* Pattern round when `compiles?` is false — it would silently
  disable most of the linter on exactly the LLM-generated population it exists
  for, and poison the `:reverted` signal the harness's bugfix lane consumes.

- [x] ~~**T3.2 [C][H] `{rule, :no_op}` in the trace.**~~ **DONE `7708aef` (credence)
  + harness `7b6e2c6`.** Both rounds were wrong, in opposite directions: Pattern
  dropped the rule from the trace entirely, while **Semantic recorded
  `{rule, 1}`** — a positive claim that it had fixed one diagnostic when the
  source came back byte-identical. Both now emit `{rule, :no_op}`. It matters
  most in Semantic, which is first-match-wins: a rule that matches and then
  declines is holding a slot no other rule can have. `Credence.rule_outcomes/0`
  is new — the closed set as data.

  **Sequel, 2026-08-17 — T3.2 made no-ops VISIBLE; it did not forbid them.**
  `test/fix_or_drop_test.exs` + `test/support/fix_or_drop.ex` now gate the stronger
  claim: no rule may report a finding that nothing repairs (Rule Standard v1.1
  requirement **2a**, docs/19). The gap mattered — 24 findings across 9 rules were
  reported and never repaired, at a fix coverage of 1486/1515 = 98.1%. Ledger
  opened at 24 and was paid to **zero** the same day: 18 findings gained a repair,
  6 were removed as unrepairable. Every one of the nine was the same defect — the
  admission decision kept in two copies, one per callback, drifted apart — so the
  repair was always to delete the second copy rather than synchronise them. Three
  were also **silent behaviour changes** (parsing, compiling, warning-free output
  returning a different answer), which no other gate can catch because
  `apply_or_revert` reverts only on non-compiling output. This closes STATUS.md's
  D10, which is deleted from the map.

  **Correction to this item's framing.** It said the harness "will silently
  drop" the new vocabulary "the moment the sister resets onto main". It has been
  dropping it *all along*: `@pair` accepted `:reverted|\d+` and `Regex.scan/3`
  **skips** a pair it cannot match rather than failing, so `:rolled_back`,
  `:patch_rejected` and `:crashed` were already discarded on every row — three
  outcomes, live, not one prospectively. A dropped pair removes the module from
  `modules/1`, so `classify.ex` then rejects a correct `BUGFIX_RULE` naming it:
  the rule most worth reporting (one that crashed) was the least reportable.
  Credence's `pattern.ex` comment asserting the harness "can consume it
  alongside `:reverted` and `:patch_rejected`" was simply false.

  The harness's outcome branch is now **generic** (`:[a-z][a-z0-9_]*`), not an
  enumeration: pinning the list would restore this failure mode on the next
  addition, and the property that matters is not "we know the vocabulary" but
  "we cannot lose a member of it". `reverted/1` is deliberately unchanged —
  widening the bugfix lane is a routing decision on its own evidence.

- [x] ~~**T3.3 [C] `mix credence.equiv` vacuous EQUIVALENT (C2.4).**~~ **DONE
  `a3a3faa`.** Both shapes now return `{:vacuous, reason}` and render as
  **SKIPPED**, never EQUIVALENT: an empty battery (`:no_admitted_inputs`) and
  every input raising identically on both sides (`:all_raised`).

  Worth stating why it mattered: `Enum.all?/2` over an empty list is `true`, so
  the task answered with its **strongest** verdict from having compared nothing
  — and since the default battery is empty for *every* multi-var snippet without
  `--dim`, that was the ordinary outcome for a whole class of rewrite, not a
  corner case. Pinned by feeding it `a - b` vs `b - a`, which is not equivalent
  by any reading and was called EQUIVALENT.

  **A second live instance fell out of the fix.** In `--minimal-set`, a switch
  whose assumption filter shrank the battery to nothing returned `:equivalent`,
  so the task reported `EQUIVALENT minimal_set=[that switch]` — naming a switch
  as the thing that makes two expressions agree, on evidence of zero inputs.
  Same root cause, same fix.

  **And the `:all_raised` clause is deliberately narrower than it first was.**
  The obvious form — "every input raised on both sides" — would reclassify a
  genuine DIVERGES (different exception classes on every input) as SKIPPED, i.e.
  hide a real behaviour change behind a vacuity guard. It now fires only where
  `ob === oa` already held, so it can only intercept verdicts that would have
  been EQUIVALENT. That narrowing has its own control. Pairs with H3 (T5.4).
- [ ] **T3.4 [C] Equivalence probe upgrades that unblock 3 diverged re-queues**
  (ledger H-A/H-B/H-C, replacing docs/16's original LD2 framing):
  (a) battery structs + `MapSet` dimensions (`%Date{}`/`%DateTime{}`/
  `%NaiveDateTime{}`/`%Task{}`) — flips 10 of 13 diverged rows to REPAIR,
  row 31; (b) tolerant `repair?/1` (`credence.equiv.ex:166-169` — it moved when
  T3.3 added the `{:vacuous, …}` clauses at the old anchor →
  `match?({:raise,_}, ob) or ob === oa`) — flips row 185, verified NOT to
  rescue row 105 (the correct kill — **row 105 is the mandatory positive
  control for any probe change**); (c) stacktrace normalization in
  `test/support/behaviour_equivalence.ex` — row 33.
- [x] ~~**T3.5 [C] `behaviour_equivalence.ex:312` `compile_module!/2` renames
  only the `defmodule` header**~~ **DONE `a3ff262`.** The rename now happens on
  the AST, so every `__aliases__` node naming the module moves with the header —
  struct literals, struct patterns, qualified self-calls alike.

  It could not be fixed on bytes: the module's name is a substring of
  `PointExtra`, appears in its own moduledoc, and a global `String.replace`
  would rewrite both. This is the same byte-scope trap `Credence.SourceMask`
  exists for, one layer up in the test harness.

  The failure was not subtle once provoked — a module whose own function says
  `%Point{}` dies in `:elixir_map.expand_struct/5`, because after a header-only
  rename `Point` no longer exists. The worse case is quieter: if an earlier test
  left a `Point` loaded, the reference resolves to *that* stale module and the
  equivalence check silently compares against the wrong code. Control: the new
  test seen red against the pre-fix implementation. Unblocks T5.5, and H4's scope
  estimate can now be re-taken against a working checker.
- [ ] **T3.6 [C] Smaller ledger FIX-CREDENCE rows — 5 of 6 done**
  (`c1d7cd7` ×2 · `77c6571` · `9184377` · `6962b7c`). Only row 183 remains, and
  only half of it: the `UndefinedFunction` decline guard landed, so the residue
  is widening `NoHallucinatedDefpstruct` to the `defpstructp` spelling. The
  4.6d deferred rows are listed separately below.

  * [x] ~~`RuleHelpers.log_diff/3` renders a fabricated diff (ledger:846)~~ —
    `diff_lines/2` paired the two files by **index**, so one inserted line
    shifted everything after it and the whole file rendered as changed. Two
    consequences, both measured: it **fabricated a bug report** (a correct module
    reorder reported to the harness as a "catastrophic replacement", ledger row
    181) and it was **what blew the log budget** — `APPLIED_RULES:` is printed
    last, so a whole-file render pushed it past Logger's 8096-byte cap. (This
    line cited "row 120"; there is no row 120 in the ledger. The truncated
    `APPLIED_RULES:` victims are rows 6/59/87/88/175/210/224, and 181 is the
    fabricated-diff one named just above.)
    Now `List.myers_difference/2`, which also drops an `Enum.at/2`-in-a-loop that
    was quadratic in file length. Pairs with the harness-side `truncate:
    :infinity` (T4.3) — the ledger prescribed both halves and this is the
    credence one.
  * [x] ~~`UndefinedFunction` decline guard (ledger:296)~~ — `match?/1` accepts
    every `undefined function …`, but the repair is a table lookup, so a call the
    tables never heard of matched and returned the source byte-identical. The
    `should_report?/2` guard **is** `fix/2` (`fix(source, d) != source`),
    deliberately: a guard that approximates the fix is a second implementation of
    the same decision and drifts from it.
  * [x] ~~`NoMapKeysOrValuesForIteration` (row 54)~~ — `rebuild_call/2` covered a
    bare local and an Elixir alias; an **Erlang module capture**,
    `&:queue.is_empty/1`, renders its module segment as
    `{:__block__, _, [:queue]}` and matched neither, raising
    `FunctionClauseError`. Reproduced live. C6's per-rule isolation now contains
    the blast radius, but the rule still crashed and never fixed anything.

    The repair refuses the **whole** rewrite, not just that argument: the fix
    replaces `Map.values(m)` with `m`, so a callback left un-destructured would
    start receiving `{k, v}` pairs where it expects a value — a silent behaviour
    change, which is strictly worse than the crash it replaces.
  * [x] ~~`Syntax.NoFnAsVariable` (row 164)~~ — reproduced live, and the cause is
    worth more than the fix: **every one of this rule's fixtures is
    module-less**. Wrap its own moduledoc "Bad" example in a `defmodule` and the
    rule stops firing entirely — after the first (pinned) rename the remaining
    `fn` sits mid-line and the parser blames the unterminated `defmodule do`,
    which carries no column. Real code always has a module, so the gap could only
    ever surface on a real row, never in its own tests. Two shapes added: an `fn`
    followed by a dot (`fn.(v)` — the keyword can never be, so it needs no
    evidence at all) and a trailing `fn` in value position. Three controls pin
    that genuine multi-clause keywords stay untouched.
  * [x] ~~`FixLocalFunctionInGuard` (rows 115/145/192/196)~~ — four rows, one
    cause: the matcher was the **literal string**
    `"cannot find or invoke local is_range/1 inside a guard"`, one name and one
    arity, so the rule's name promised a general repair its matcher never
    attempted. Now matches any local/arity and inlines the helper when — and only
    when — the body is a single expression built from its own parameters,
    literals and calls a guard permits. Rows 145 and 192 now repair; row 115
    correctly declines, because `byte_size(String.trim(l)) == 0` looks inlinable
    but `String.trim/1` is not guard-legal, so inlining would swap one compile
    error for another.

    Row 196 was the other half: it matched `when is_range(r)` with nothing
    defining `is_range`, returned the source unchanged, and thereby **consumed**
    the diagnostic. Fixed in two places — a `should_report?/2` decline, and
    `lib/semantic.ex` now hands a diagnostic to the next matching rule when the
    first no-ops. docs/20 §3 says one diagnostic has one owner; that makes it
    true by *doing the repair* rather than by sorting first.
  * [ ] remaining:
    `NoHallucinatedDefpstruct` + `UndefinedFunction` interaction (row 183), and
    the 4.6d deferred salvage rows.

  Original: (each is one rule, evidence
  at the cited ledger row): `FixLocalFunctionInGuard` (rows 115/145/192/196 —
  one also touches `NoHallucinatedGuardFn`); `NoMapKeysOrValuesForIteration`
  (row 54, line ~374); `Syntax.NoFnAsVariable` (row 164);
  `NoHallucinatedDefpstruct` + `UndefinedFunction` interaction (row 183);
  `UndefinedFunction` decline guard (ledger:296); `RuleHelpers.log_diff/3`
  renders a fabricated diff (ledger:846, `lib/rule_helpers.ex:938`). Also the
  4.6d deferred salvage rows (`Agent`, `NaiveDateTime`, `List.keystore`,
  `exit/2`) — sound but blocked on call-boundary anchoring; `exit/2` also
  needs an arity check `replace_call_on_line/4` doesn't do.

- [x] ~~**T3.7 [C] `FixScientificNotation` + `FixPythonFloorDiv` still corrupt
  string literals — and docs/16 claims they were fixed.**~~ **DONE `e81985e`.**
  Both rules now match a `Credence.SourceMask` shadow and splice byte ranges into
  the real line, exactly as `FixPythonModulo` does. That closes the 4.6a family:
  all four line-based syntax rules are converted, and the CHANGELOG, docs/16 and
  `docs/PR_BODY_phase4.md` all say so truthfully for the first time.

  **Correction to this item's own claim — it understated the defect.** This item
  named one shape. Six were live, and the extra four fell out of *probing* the
  two that were written down:

      IO.puts("version 1e5 build")   ->  IO.puts("version 1.0e5 build")
      IO.puts("ratio 7 // 2 here")   ->  IO.puts("ratio div(7, 2) here")
      x = 1e5  # bump to 1e9 later   ->  x = 1.0e5  # bump to 1.0e9 later
      x = a // b  # was a // b       ->  x = div(a, b)  # was div(a, b)
      ~S(raw 1e5)                    ->  ~S(raw 1.0e5)
      ~c"tolerance 1e-10"            ->  ~c"tolerance 1.0e-10"

  The trailing-comment shape is the one to carry forward.
  `String.starts_with?(String.trim(line), "#")` *reads* as "comments are safe"
  and protects only a line that begins with one — so the guard covered the case
  nobody writes and missed the case everybody does. Heredoc bodies were
  unguarded too. Note the recursion: this is the third time this row has been
  written from reading rather than running, and the third time running it changed
  the answer.

  `FixPythonFloorDiv` was not a mechanical swap. It ran two regexes in sequence,
  and after the first rewrite the shadow no longer aligns with the line, so both
  patterns are now collected from the shadow in one pass, merged by offset and
  spliced once. That also settles `a // Kernel.//(b)`, where the two patterns
  overlap and the old sequential form emitted `div(a, div)(b)`.

  Two deliberate behaviour changes, both toward doing less harm: a `..//` range
  step *inside a string* no longer declines the whole line, and a comment is
  blanked wherever it starts. 22 positive controls, 22/22 seen red against the
  pre-fix rules with the 70 pre-existing tests still green.

  **The family was not closed by that commit.** `8169601`: `FixDivRem` — one of
  the two rules this item, docs/16 and the CHANGELOG all named as *already*
  converted — was masking correctly in `analyze/1` and **one line at a time** in
  `fix/1`, which a line cannot be, because heredoc and multi-line-string state
  crosses lines. So it rewrote its own moduledoc while `analyze` correctly
  reported nothing: the rule fixed what it had never found, and the finding a
  reviewer reads and the edit that ships came from different pictures of the
  file. Repaired with an invariant rather than a rewrite — the per-line machinery
  runs only where masking the line alone agrees with the whole-file mask.

  It was found by an **oracle, not by reading**, which is the transferable part.
  See T3.10.
- [x] ~~**T3.8 [C] The two rules T1 proved cannot fire.**~~ **DONE — both are alive.** Per the project's
  standing rule, deletion is never the first move — extract the verified failure
  mode first, then retire or rebuild:
  - [x] ~~`Syntax.FixMalformedSpec`~~ **DONE — re-homed to Semantic.** The
    premise was false: `@spec f(a :: b)` parses, so the Syntax phase never ran on
    it, and its moduledoc's "## Bad (won't parse)" is exactly the assertion one
    `Code.string_to_quoted/1` call at authoring time would have refuted.

    **Correction to this item's own recommendation: not Pattern.** It said the
    failure mode "belongs in **Pattern**, where the AST is available". Running it
    says otherwise — the line parses and then fails to *compile*, emitting a
    precise `severity: :error` diagnostic that **no live rule claimed**:

        type specification missing return type: max_product(list(integer()) :: integer())

    A compiler diagnostic is the Semantic phase's input by definition, so Pattern
    would have been a second wrong phase for the same rule. Now
    `lib/semantic/fix_malformed_spec.ex`, keyed on that message, with the rewrite
    transplanted unchanged. It witnesses through real dispatch (`{FixMalformedSpec,
    1}` in `applied_rules`), so it leaves the T1 `@ledger` *and* the T3.10
    self-corruption ledger — the latter by leaving the phase the oracle scans.

    The port had a defect T1 caught immediately: the Issue kept its old Syntax
    atom `:malformed_spec`, but Semantic and Pattern issues are attributed by a
    **module-derived** atom, so the rule was live and unattributable. Only Syntax
    atoms are author-chosen. Two Semantic meta-gates then required an output-parses
    assertion and an attribution assertion the ported tests did not have.
  - [x] ~~`Semantic.FixWithElseBareValue`~~ **DONE — re-keyed, not retired.** It
    matched `expected -> clauses for :else in "with"`. Elixir 1.20.2 emits
    `invalid "else" block in "with", it expects "pattern -> expr" clauses`, and
    **no live rule claimed that**. So the rule was dead on arrival and shipped
    that way — while its own tests passed, because they handed it a
    hand-written diagnostic map carrying the string the rule expected. The rule
    and its tests agreed about a message the compiler never produced. That is
    the G1 class exactly, and the reason T1 exists.

    **Only the key was wrong. `fix/2` was correct the whole time** — fed the
    diagnostic by hand it already produced valid, compiling output, so the
    repair is one attribute and the rule is now live. Both spellings are
    matched; only the 1.20.2 one is verified here by compiling a fixture, and
    the legacy one is kept because this project supports `~> 1.17`. The new
    tests obtain the diagnostic by compiling, assert the fixture parses but does
    not compile, assert no second rule claims the message (first-match-wins
    dispatch would otherwise decide which one is dead), and assert the end-to-end
    repair through real dispatch.
- [x] ~~**T3.10 [C] Pay down the self-corruption ledger.**~~ **DONE — 10 of 11;
  the 11th is T3.10a and stays on purpose. See the resolution at the end of this
  item.**
  The gate is in (`b41af7b`, `test/self_corruption_test.exs` +
  `test/support/self_corruption.ex`); the debt is being worked down against it.
  Run every Syntax rule's `fix/1` over its own `.ex` file — a rule's moduledoc is
  *required* by the Rule Standard to contain the exact byte sequences it rewrites,
  inside a heredoc, beside prose naming the operator in English. A rule that
  rewrites its own documentation cannot tell code from prose. **11 of 45 did**,
  over 253 lines:

  | rule | lines | status |
  |---|---|---|
  | `no_else_if` | 226 | ⬜ **deliberately not converted** — see T3.10a |
  | `fix_do_block_fusion` | 6 | ✅ masking, **threaded through the cascade** |
  | `fix_python_augmented_assignment` | 4 | ✅ masking — **plus a second defect underneath** |
  | `fix_truncated_binary_close` | 4 | ✅ `becd59b` — masking, the family default |
  | `no_fn_with_capture` | 4 | ✅ masking, replacing a `#`-only guard |
  | `fix_stale_access_modifier` | 3 | ✅ masking, the family default |
  | `fix_assignment_dot_syntax` | 2 | ✅ masking; retired a guard it subsumes |
  | `fix_malformed_spec` | 1 | ✅ **not a repair** — the rule was dead; re-homed to Semantic (T3.8) |
  | `prefer_spec_arrow_operator` | 1 | ✅ masking **for the decision only** — it rebuilds, not splices |
  | `no_doc_with_do_block` | 1 | ✅ `643435a` — **not** the shadow; `self_contained?/2` |
  | `prefer_cond_do_keyword` | 1 | ✅ `becd59b` — **not** masking; a parse guard |

  The usual repair is `Credence.SourceMask`, with `fix_python_modulo.ex` as the
  reference and `fix_python_floor_div.ex` as the two-pattern-merge variant. Two
  traps, both already paid for once: **mask the whole file, never a line alone**
  (T3.7's `FixDivRem` finding), and **make `analyze` and `fix` read the same
  shadow** or the rule fixes what it never reported.

  **The lesson from the first three: it is not one repair.** All three needed a
  different mechanism, and applying the family default to the wrong rule is not a
  no-op — it is a silent retirement. `no_doc_with_do_block`'s pattern keys on the
  `"` quotes of `@doc "..."`, and masking blanks a literal's quotes along with its
  body, so on the shadow it would have matched *nothing, ever*: green here, green
  in its own tests, and quietly dead. `prefer_cond_do_keyword` was not a literal
  problem at all — its gate proved the *result* parses rather than that the
  replacement repaired anything, so on already-parsing source every candidate
  qualified. Diagnose before converting.

  Two supports came out of this and are worth reusing:
  `Credence.SourceMask.self_contained?/2` (is this line inside a multi-line
  literal? — for patterns that key on delimiters masking would blank), and
  `test/source_mask_test.exs`, which did not exist: the module behind every
  byte-scope repair in the tree had no test of its own.

  Known trap for the remaining eight, from a read-only analysis pass:
  `fix_do_block_fusion` is a **five-stage cascade** whose stages change byte
  length and feed each other (`) do: ` → `), do: ` grows one byte, and stage 5
  only fires on stage 2's output — pinned by a live test). It cannot use the
  collect-all-matches-then-splice-once idiom, and it must not re-mask between
  stages, since masking a line alone is the `FixDivRem` defect. The shadow has to
  be carried through the cascade, receiving the identical splice at each stage.

  **Resolution — the ledger is down to its one deliberate entry.** All six
  remaining convertible rules are paid down and off it; the scan now returns
  `%{"no_else_if" => 226}` and nothing else. The read-only pass's warning about
  `fix_do_block_fusion` was accurate and was implemented as stated: the
  `{line, shadow}` pair is threaded through all five stages, each splicing the
  identical bytes into both, which keeps the pair valid (same byte length, same
  code bytes) for the stage that follows.

  **"It is not one repair" held all the way to the end.** Six masking bugs still
  needed three distinct mechanisms:

  * `prefer_spec_arrow_operator` **rebuilds** its line from parsed parts rather
    than splicing byte ranges. Masking the rebuild would have emitted blanked
    literals, so the shadow answers only *is this line code?* and the rewrite
    reads the real line.
  * `fix_do_block_fusion` needed the threaded shadow above.
  * the other four are the family default — locate in the shadow, splice from the
    line — and two of them retired hand-written guards the shadow strictly
    subsumes.

  **The finding worth carrying: knowing about the class is not being guarded
  against it.** `no_fn_with_capture` already carried a guard *and* a comment
  saying that rewriting non-code content "would corrupt" it. The guard skipped
  lines starting with `#`. So it protected comments and missed heredocs entirely,
  and the rule rewrote three sentences of its own moduledoc prose from naming the
  broken form to naming the fixed one — leaving documentation that no longer said
  what the rule repairs. `fix_assignment_dot_syntax` and
  `fix_python_augmented_assignment` both went further and *argued in their
  moduledocs* that literals were safe, on reasoning that was true only by
  accident of `^`-anchoring — an accident that runs out inside a heredoc, where a
  documentation line may begin with exactly the matched shape.

  **And one rule had a second defect underneath the first.** Converting
  `fix_python_augmented_assignment` exposed that its right-hand side ran to the
  end of the line, so a trailing comment was captured as part of the expression:
  `count += 1  # total` became `count = count + (1  # total)`, putting the
  closing paren inside the comment. **The output did not parse at all** — run,
  not read, on six inputs, three of which failed. This is T3.7's "trailing
  comment nobody guarded" in a fifth rule. The shadow settles it: a comment is
  blanked to the line's end, and the raw byte at the start of that blank run
  separates a comment from a trailing *string*, which is part of the expression.
  The comment is now preserved after the rewritten statement instead of being
  swallowed by it. Worth stating plainly: **converting a rule for the ledger's
  reason found a live defect the ledger was not looking for.**

  Left unrepaired and recorded here rather than fixed: the same rule swallows a
  second statement when one line holds two (`count += 1 ; total += 2` →
  `count = count + (1 ; total += 2)`, which does not parse). That is not a
  literal-awareness bug and the rule's documented contract is "a standalone
  statement", so it is out of this item's scope — but it is executed, real, and
  now written down.

  Each of the six gained a `LITERALS` test block ending in the same pin — `fix/1`
  over the rule's own source file must be a no-op — so the oracle's finding is
  now a unit test per rule and not only a tree-wide gate. Positive control: with
  the six rules reverted and the tests kept, **32 of 163 go red** across all six
  plus the gate itself, while the 131 pre-existing tests stay green. Full suite:
  **9,911 tests + 6 properties, 0 failures.**

- [x] ~~**T3.10a [C] `no_else_if` — do NOT convert it. It has four confirmed
  defects that masking does not touch, and its ledger entry is the only thing
  flagging them.**~~ **DONE — and the answer was not to convert it but to RETIRE
  it; see the resolution at the end of this item.** This started as "the outlier
  at 226 lines" and became the most serious finding on the ledger. Everything
  below was **run**, not read:

  * **The 226 is an artifact.** `fix/1` on its own file removes 2 lines, and the
    scan's positional diff then counts every subsequent line as changed
    (`241 → 239` lines, 226 positional differences). The real prose corruption is
    ~7 lines, all inside its own `@moduledoc`. **So the ledger's line count is
    not a proxy for severity when the rule changes line count** — `no_else_if`
    sat at the top of the paydown order for the wrong reason, and the ordering
    note above should be read with that caveat.
  * **It corrupts valid, parsing code.** Given `if a do … else if b do … else …
    end end` — which *parses*, because `else if` is legal Elixir (`else` plus a
    nested `if` opening its own block) — it emits a `cond do … end` plus a stray
    `end`, and the output **does not parse**. Verified both directions. Its
    trigger token is genuinely ambiguous and the rule assumes the broken reading
    unconditionally. The discriminator it lacks is the `end` count at the chain's
    indent: 1 means the broken transplant, N+1 means valid nested `if`.
  * **Three boundary cases produce non-parsing output**: a missing terminator
    (swallows to EOF), `else # note` (folds the else body into the previous
    branch), and an empty branch body (emits a bodyless `cond` clause). The empty
    body case also raises an Elixir *runtime warning* from
    `no_else_if.ex:135` — `Range.new/2` with `last < first` — so there is a
    latent negative-range bug under it.
  * **Its sibling `fix_elsif_in_if_chain` is hardened against all of these**, in
    its very first commit, by a reviewing agent whose log enumerates the same six
    defects. A third copy (`no_elsif_keyword`) was **rejected in review for being
    the pre-hardening copy of that rule**. `no_else_if` is that same artifact — it
    landed five weeks earlier, through a gate that did not exist yet.
  * **The pipeline partially protects users.** On a mixed chain the sibling
    declines and `no_else_if` then rewrites it, but `fix_with_trace` shows
    `{Credence.Syntax.NoElseIf, :reverted}` — the C4 revert gate catches that one.
    That bounds the blast radius; it does not make the rule correct, and it does
    not cover the valid-nested-if case, which the phase never sees because that
    source parses.

  **Why converting it would be actively harmful.** Masking its trigger *does*
  clear the ledger entry — verified, the shadow has zero `^\s*else\s+if` hits
  against 1 raw hit. It would also turn the gate green over four live corruption
  modes and burn the one signal that surfaced them. `no_else_if` stays on the
  ledger deliberately until the design question below is answered.

  **The design question, and the recommended sequence.** The two rules' triggers
  are provably disjoint (`^\s*els?if\b` cannot match `else if`), so this is not a
  duplicate in the C11 sense — it is one failure mode with two spellings and only
  one hardened implementation. Recommended, and explicitly a maintainer decision:
  (1) copy `no_else_if`'s 14 assertions into the sibling's test files, **red**;
  (2) widen the sibling's `@elsif_re` to `~r/^\s*(?:els?if|else\s+if)\b/` and add
  the `end`-count discriminator, asserting `elsif`/`elif` output is byte-identical
  before and after the widen — commit `fe6c2f7` is the template for exactly this
  move; (3) run `no_else_if`'s tests against the sibling unmodified; (4) retire
  `no_else_if` only once (3) is green. Test coverage today is 37 assertions for
  the sibling against 14 for `no_else_if`, and *none* of `no_else_if`'s 14
  involves a string, a heredoc, a comment on the `else` line, a missing
  terminator, or surrounding code.

  **DONE — all four steps. `no_else_if` is retired and the self-corruption ledger
  is empty.** Step 4 was taken by the maintainer's explicit decision after steps
  1–3 put the evidence in place; the sequence below is what that evidence was.

  * **The widen (step 2) is in.** `@elsif_re` and the condition extractor now
    match all three spellings. `elsif`/`elif` output was proved **byte-identical
    before and after** — not inferred from the green suite but measured, by
    running an 18-case corpus through the rule with the change applied and again
    with it stashed, and diffing. Zero bytes differ.
  * **The discriminator is in, and scoped.** `one_terminator/4` declines an
    `else if` chain carrying more than one terminator at the header's
    indentation. It is consulted *only* for the `else if` spelling, which is what
    makes the byte-identity above true by construction rather than by luck:
    `elsif`/`elif` are not Elixir, so no valid reading of them exists to
    discriminate against.
  * **Step 3 was run, and the sibling covers all seven of `no_else_if`'s
    scenarios** — identically on six, and on the seventh (comment-only `else`
    body) it differs only in where the comment sits relative to the `nil`. Both
    parse; the sibling puts the comment above the value.
  * **All four corruption modes were re-run side by side, and the sibling is
    correct on every one.** Valid nested `if` (input **parses**): `no_else_if`
    emits a `cond` plus a stray `end` that does not parse — the sibling declines.
    Missing terminator: `no_else_if` swallows to EOF — the sibling declines.
    `else # note`: `no_else_if` emits non-parsing output — the sibling declines.
    Empty branch body: `no_else_if` emits a bodyless `a ->` clause that does not
    parse *and* raises the `Range.new/2` negative-range warning from
    `no_else_if.ex:109` — the sibling emits `a -> nil`, which parses.
  * **Two positive controls, deliberately separate**, because one perturbation
    could not have proved both halves: reverting the widen reddens **5** tests
    (the rewrites) while every "declines" test stays green — those pass vacuously
    against a rule that never matched `else if`. Keeping the widen and disabling
    only the discriminator reddens **exactly one**: the valid-nested-`if`
    decline. The discriminator is isolated and load-bearing.

  One thing this work corrected in the existing tests: a test named *"does not
  touch `else if`, which is valid Elixir"* — whose body is the properly nested
  multi-line form, still untouched, but whose name asserted a general claim the
  widen makes false. Renamed to say what it actually pins.

  **Step 4, taken.** `lib/syntax/no_else_if.ex` and its two test files are
  deleted. The rule was strictly dominated: the sibling handles every shape it
  handled and four it corrupted, and because the sibling runs first (index 8 vs 28
  in `default_rules/0`) with the Syntax phase a cascade rather than
  first-match-wins, `no_else_if` had already been reduced to seeing only what the
  sibling declined — precisely the set it got wrong.

  Deleting a rule is only safe while its behaviour is pinned somewhere else, so
  the two `else if` describe blocks in
  `test/syntax/fix_elsif_in_if_chain_fix_test.exs` are now the surviving record of
  everything it could do, and say so in a comment. FM-ELSE-IF above is the
  failure mode, written out before the rule went, per the standing rule that a
  rule's value is its failure mode.

  **The gate's own vacuity test had to be rebuilt, and this is the interesting
  part.** It asserted "some Syntax rule still corrupts its own source" — a sound
  check against a *non-empty* ledger and a worthless one the moment the debt
  reaches zero, because that is exactly when "nobody corrupts" and "the differ
  stopped working" become the same observation from outside. Paying a ledger down
  to empty therefore *disarms the gate that measured it*, which is a trap any
  ratchet built this way will hit on its last entry.

  The fix moves the vacuity check from the result to the machinery:
  `Credence.SelfCorruption.corrupted_lines/2` is now public, and the gate hands it
  a rule that certainly rewrites what it is given (must report a change), one that
  certainly does not (must report none), and one that raises (must count as a hit,
  not a skip). GREEN-0 and its perturbations, independent of whether any real rule
  is broken. That is strictly stronger than what it replaced.

  **The failure mode, written out first so retiring the rule cannot lose it —
  FM-ELSE-IF.** An LLM translating Python emits `else if <expr> do` at branch
  indent, meaning `elif`. Elixir reads it as `else` plus a nested `if` that opens
  its own block, so a chain with N `else if` headers needs **N+1** `end`s and the
  author wrote 1. Every token is legal and the construct is legal; the failure is
  arithmetic on block terminators, and the parser can only report it at the
  outermost unclosed `do` — usually the `defmodule` line, tens of lines above the
  mistake, naming neither `else` nor `if`. The repair is to collapse the ladder to
  `cond do`, supplying `true -> nil` when there is no trailing `else` (a nested
  `if` yields `nil` where `cond` would raise `CondClauseError`). The
  discriminator that makes it safe is the `end` count above. Prevalence in LLM
  output is **unmeasured** — the corpus has zero hits, but the corpus by
  construction holds only files that parse, so it cannot answer this. That is a
  reason to preserve the failure mode carefully, not a reason to weaken the
  repair.

- [x] ~~**T3.9 [C] 57 files fail `mix format --check-formatted` at HEAD.**~~
  **DONE `f564e31` (maintainer).** Pre-existing drift, not from any code change
  — Elixir 1.20's formatter against a tree last formatted by an older version,
  confirmed by stashing (a clean tree failed too). Reformatted in one isolated
  commit, which is the right shape for it: the diff touches 57 files and would
  have buried any change it rode along with. `mix format --check-formatted` now
  passes tree-wide, so a bare `mix format` no longer ambushes anyone.

### Tier 4 — harness correctness (make the loop trustworthy for weak models)

- [x] ~~**T4.1 [H] Implement the STATUS.md interlock — it is documented but does
  not exist.**~~ **DONE `24f2dee`.** `STATUS.md` and docs/21 describe `mix cev.preflight` refusing
  to run while the mode file says CATCHING UP; **no code in the harness reads
  STATUS.md at all** (grep-verified; both docs corrected this session to say
  so). Add a static check in `Cev.Preflight` reading the *accepting* repo's
  `STATUS.md` (path decision needed — not the sister clone's copy), failing
  while `MODE: CATCHING UP`. Until then the interlock is prose.
- [ ] **T4.2 [H] BUGFIX-lane evidence gates — (a), (b) and (e) DONE (`c07fb57`,
  `1f62e16`); (c) and (d) remain.** (a) rejects a BUGFIX whose BEFORE equals its
  AFTER; (b) treats an all-rule-character body (`===`, `---`) as blank — one
  instance burned an 80-turn session, and the emptiness test is deliberately
  `\\A[-=_*\\s]+\\z` because the looser forms start eating real code; (e) is
  `Cev.Premise`, one compile that refutes a premise before an implementer run is
  spent on it. (e) checks the mechanical statement rather than the prose:
  a Semantic BEFORE with no diagnostic has nothing to key on, a Syntax BEFORE
  that parses is inert by construction. Pattern is exempt — no diagnostic is its
  normal state — and inconclusive always passes, because this gate exists to
  catch a *refuted* premise. It compiles model source, so it is bounded like
  credence's T3.11, and its test feeds it the very expression that OOMed the box.
  Original (the single biggest weak-model
  lever after T1; ledger clusters H-A/H-B): (a) reject `:bugfix_rule` when
  `before == after`; (b) treat an all-`=` section body as blank
  (`parser.ex:121-122` passes `"==="` through — burned an 80-turn session);
  (c) require the classifier to quote the verbatim offending line from the
  `credence_fix` trace; (d) **validate the repro against the accused rule
  mechanically** — derive the accusation from `source CHANGED` trace lines,
  preserve the workspace file as fixture, and "if the reduced repro does not
  make the accused rule fire, fail the row" (rows 40/50/59: three live
  over-fires the harness talked itself out of); (e) **premise-verification** —
  compile the classifier's BEFORE and require the claimed diagnostic to appear
  (~one compile; would have killed rows 150/162/221 ≈ $100 of implementer
  budget in nine reviewed rows alone).
- [x] ~~**T4.3 [H] LD1 residuals**~~ **DONE `5aadc9d` · `2bb104d` · `bc94f07` +
  the row-54 signal.** All parts landed; the sub-items are struck below with what
  each turned out to be. The one finding that reframes the item: **all of the
  parse-side losses had a single root cause — Elixir's `Logger` truncates a
  message at 8096 bytes by default**, and this harness does not read those logs,
  it *parses* them as data. A row firing ~150 rules puts the `APPLIED_RULES:`
  line within a few hundred bytes of that cap, so the evidence was being cut on
  exactly the busiest rows. `truncate: :infinity` fixes it at source and is pinned
  by a test, because a finite cap is silent data loss waiting for a longer row.

  Original item text (each part now done): (the closed-set story after H12): name
  normalisation in `parser.ex:78-83` (`<phase>/<snake>` →
  `Credence.<Phase>.<CamelCase>`, resolve by basename on wrong phase — row
  95); prompt/gate reconciliation — the prompt solicits under-fire reports the
  validator must reject (`prompt.ex:110-115,221-222` vs `classify.ex:115`);
  either add a `RULE_UNDER_FIRED` decision or stop soliciting (19 rows named
  real rules that genuinely did not fire — "The gate was right; the prompt was
  wrong"); `applied_rules.ex:16` requires the closing `]` (mid-list truncation
  discards the whole line); fix-script `exit != 0` as a distinct escalatable
  signal (row 54); **the distilled log the classifier reads is still
  8096-byte-truncated** — add `:truncate` config or read from sidecars
  (H12 rescued the closed set, not the evidence), and `extract_diagnostic/1`
  (`router.ex:407-414`) should read the sidecar, not the truncated log, and
  hand over *all* unmatched diagnostics, not the last one.
- [x] ~~**T4.4 [H] Seed teaching gaps — six, each a gate the model currently
  learns about only by failing**~~ **DONE `993c367`** — all six stated up front,
  with the C2.2 entry carrying the *mechanical trigger* (an integer and a float
  that are `==` inside the same input) rather than "use a dimension", and the
  leaf-token line quoted verbatim from the ledger. Also adds the seed's first
  positive exemplar: it taught entirely by prohibition before.
  Original: (grep-verified against
  `lib/cev/implement/seed.ex`): (1) C2.2 operation→dimension mapping (the
  seed names "a Credence.EquivalenceInputs dimension" generically; a
  Map-rewriting rule picking `term_lists` fails the meta-gate with no prior
  warning); (2) C13 budget existence (over-fires are drops, not accepts);
  (3) C8 one-diagnostic-one-owner + the decline-guard idiom
  (`should_report?/2` rather than claim-then-no-op); (4) the leaf-token /
  sentinel-guard anti-patterns (ledger:73 prescribes the exact prompt line;
  three of four Phase-5 over-fires were context-free leaf matches); (5) a
  worked filled-rule exemplar (H8's seed half — the seed currently teaches
  only by prohibition); (6) first-match-wins dispatch semantics (an
  over-broad `match?/1` starves every other rule).
- [x] ~~**T4.5 [H] H9 implementer half — environmental kills booked as merit
  failures:**~~ **DONE `98bcddf`.** All three shapes plus the reporting gap. The
  framing worth keeping: the cost of misbooking these is not a lost row, it is a
  wrong entry in decisions.md, which then teaches the next pass that a good idea
  is a dead end. Also: `retries_exhausted` reported the first 400 bytes of the
  output, and ExUnit prints its failure detail last — so the report was reliably
  the least informative 400 bytes available. Original: zero-write null runs (row 6: 25 read-only steps, scaffold
  placeholders untouched, booked `cc_tests_red`), 429 quota kills (row 55),
  provider refusals (row 169 — key on the refusal string). Files:
  `implement.ex:55-71,82-89`, `router.ex:260-266`, `claude_code.ex` step
  accounting. Also `implement.ex:65` reports only `String.slice(failures, 0,
  400)` with no exit code and no leg attribution — the rows-100/119 mechanism.
- [x] ~~**T4.6 [H] H5 — Gate contract tests + wall-clock timeouts.**~~ **DONE
  `7922767`.** `Cev.MixTest` caps every shelled-out `mix test` (coreutils
  `timeout`, not a Task — killing the Elixir process that owns a port does not
  kill the OS process on the other end). A fired cap routes as **environmental**,
  not red, so the candidate's patch is preserved rather than judged on a suite
  that never finished. The external contract it rests on — that `timeout` exits
  124 — is executed, not assumed. Contract tests for the three diff-only rejects
  plus the mutation snapshot/restore round-trip, which matters because a wrong
  restore destroys the candidate being judged. Original:
  `gate.ex:461-473` and `implement.ex:248-253` run `mix test` with **no
  timeout**; one hung suite hangs the run. Contract tests for the five reject
  paths + mutation snapshot/restore + scratch sweep, each with a fixture
  bad-rule seen red.
- [ ] **T4.7 [H] H19 — flake-aware Gate.** H9's retry covers only
  `:did_not_run`; a genuinely *red* flake still hard-rejects with no re-run.
  Re-run failing files once; non-reproducing + outside the staged diff →
  `flaky.jsonl` + proceed; plus a pre-commit stability re-run of the
  candidate's focused tests.
- [ ] **T4.8 [H] H6 — bounded auto-retry on corpus rejects** (one repair round
  re-seeding the implementer with the corpus findings; auto-repin scoped
  `gone` lines of the rule under bugfix). **T2.1 lands first** — its scoped
  scan is what makes the retry cheap.
- [ ] **T4.9 [H] H1 — gold over-fire ratchet** (docs/14-corrected form: 76/304
  golds carry findings, so diff against an accepted-gold-findings snapshot,
  never zero-assert; per-row post-sanity + per-candidate at the Gate; 1.1 s
  full-gold scan measured). **H2 — executable fix-safety oracle** (gold +
  passing solve, single-rule fix, re-run the subject's own harness; 0.6
  s/subject standalone). H2 needs H10's solve archive.
- [ ] **T4.10 [H] H4 (scoped per E5), H7 (span-overlap rescue per E8), H3
  (equiv reach: multi-var, `--dim` inference, module-mode; `extract/1`
  `:error` must log `:skipped`, not silently bypass), H10 (birth certificates
  + "record what actually executed"), H11 (`mix cev.report` + difficulty
  join), H16 (solve-prompt deps one-liner, `solve.ex:38`), H17 (spine unit
  tests: validator ordering, novelty, distill, seed, git commit flow), H18
  (spec-entailment judge). Specs in `IMPROVEMENTS.md` with docs/14
  corrections; sequence per docs/16 Phase 8 tiers (8.2→8.6).

### Tier 5 — the standard's remaining teeth (credence quality program)

- [ ] **T5.1 [C] C14 sweep — the 40 ledgered rules.** 17 family-attributed
  first (the paydown order in `dsl_static_scan_test.exs:86-104`), then the 23
  unattributed. Each: read the rule, declare `unsafe_in_dsl/0` or earn
  `@verified_dsl_safe` with a written reason; ledger shrinks; delete the sweep
  tooling when empty (docs/19 §3).
- [ ] **T5.2 [C] C13(b) paydown — the stated action is REFUTED; see STATUS.md D4.**
  This item said *"`prefer_heredoc_for_multi_line_doc` (1,298 = 20%) first —
  narrow, demote behind an opt-in, or retire"*, inheriting C13's argument that
  *"a rule that fires thousands of times on idiomatic production code is a style
  rule"*. **Measured 2026-08-16: the premise is false.** All **1,298** of that
  rule's accepted findings, and all **167** of `no_trailing_newline_in_doc`'s,
  are inside `lib/generated/` — two projects, 202 files. Outside generated code
  both rules fire **zero** times across ~19,400 hand-written `.ex` files. All
  three proposed actions would be acting on a measurement artifact: nobody had
  read a path, only a count.

  What remains here is a corpus-composition question, not a rule question, and
  it is framed for decision in `STATUS.md` **D4**. The `prefer_erlang_float`
  taste review and the `corpus_whitelist_validator` cadence run are unaffected
  and still open.

- [ ] **T5.3 [C] C15 rule-card template + intent line** — one-sentence intent
  first (feeds the dedup index that T2.2's H8 consumes), Bad/Good, safety
  argument; enforce via meta-test; backfill mechanically. Directly improves
  the classifier's dedup signal.
- [ ] **T5.4 [C] C12 alpha-rename generality** (docs/12:297-314) + retire/
  generalize the three named over-fit rules. Rule Standard item 7.
- [ ] **T5.5 [C] C2.3 seeded StreamData layer** (after T3.4/T3.5 so the
  battery and module-compile plumbing are sound).
- [x] ~~**T5.6 [C] C6 second half — sandboxed compiles with timeout.**~~ **DONE
  `1ddbfe6`** — landed as T3.11 before anyone noticed it was already this item.
  Worth recording as a hit for the item's own reasoning: it predicted "a
  pathological fixture hangs the suite", and a pathological fixture is exactly
  what took the box down seven times on 2026-07-28.

  Delivered as specified, with two deliberate departures:

  * **`spawn_monitor`, not a supervised `Task`.** A `Task` links, so a child
    killed by the heap ceiling propagates the exit to the caller — which is the
    behaviour being prevented. `Task.Supervisor.async_nolink` would work but
    buys a supervision tree for a process with no restart semantics: the answer
    to a runaway compile is never to run it again.
  * **A heap ceiling as well as the timeout.** The item asked only for a
    timeout, and a timeout alone would not have helped: the fixture that killed
    the box reaches 62 GB in under six minutes, so any deadline loose enough to
    permit a slow legitimate compile is far too loose to stop it. Memory was the
    binding constraint, not time.

  Residual trust model documented on `compile_and_capture/1`: `System.halt/0` in
  analysed source still stops the VM and nothing in-process can prevent it. The
  honest statement is that credence executes what it analyses, and now fails
  loudly instead of fatally. T4.6 (the harness sibling — `mix test` with no
  timeout in the Gate) is still open.
- [ ] **T5.7 [C] C9 hot-path** (parse-once per pass, memoized discovery),
  **C10 observability** (Issue `column`, per-rule patch ranges, telemetry —
  note the trace vocabulary has since grown: `:reverted | :patch_rejected |
  :crashed` and docs/19 row D records nothing downstream consumes them; C10
  is that consumer), **C11 duplicate folds** (grapheme/count clusters + the
  drain watch-list pairs), **C16 remaining bullets** (docs/01 has its
  historical banner now; config surface `max_passes`/compile-timeout/fixpoint
  passes once C6/C7 land; `rule_status/1` exposing `priority` +
  `unsafe_in_dsl`).
- [x] ~~**T5.9 [C] Pay down the T1 witness ledger.**~~ **DONE — the ledger is
  empty and `@ledger %{}` is now pinned by the gate's own tests. Every rule in
  all three phases witnesses its own failure mode through the real pipeline —
  290 of 290 when this was written, **289** today (157 Pattern / 89 Semantic /
  43 Syntax) after `no_else_if`'s retirement. The gate counts at runtime, so the
  property held across the change; only this sentence needed correcting.**
  The ledger only shrinks; each reason had its own repair, and the eight entries
  turned out to name four different defects — none of which meant "this rule is
  fine":
  - [x] ~~**4 `:dep_gated`**~~ **DONE.** `plug ~> 1.16` and `nimble_csv ~> 1.2`
    added as `only: :test, runtime: false`; all four witness immediately, with no
    change to any rule. The alternative — a `test/support` stub reproducing the
    message — costs no dependency but proves less, because what it witnesses is
    the stub. Worth stating plainly what the entry meant: these rules were never
    broken. `:dep_gated` was a property of *this checkout*, and the four were
    alive in the harness workspace the whole time.
  - [x] ~~**2 `:no_fixture`**~~ **DONE.** `NoHallucinatedDatetimeZone` was
    exactly as this item described: `def f(%DateTime{} = dt), do: dt.zone`
    produces the warning, the rule wins it, and `dt.zone -> dt.time_zone` lands
    end-to-end. A *closed* struct type is required — the `is_struct/2` guard form
    the existing fixtures use refines to an open map and the compiler emits
    nothing, which is verified here as its own test, since it is the reason the
    entry existed.

    **Correction: this item was wrong about the second one, and in the direction
    that matters.** It said `{:error, %Task.TimeoutError{}}` in expression
    position "produces the error and the rule wins it". Both true, and *not a
    witness*: the rule matches, wins its slot, and then applies as
    `{rule, :no_op}` — its `fix/2` only rewrites
    `{:exit, {%Task.TimeoutError{}, _stacktrace}}`, which is a **pattern**. And a
    pattern emits a *different* message (`struct Task.TimeoutError is undefined`)
    that `match?/1` did not accept. So `match?/1` and `fix/2` were keyed to
    disjoint situations — the rule could match, or be applicable, never both.
    That is why no fixture witnessed it, and why writing one was never going to
    be the repair. Both messages are matched now; the documented shape witnesses
    in a `fn` clause and in a function head.

    Worth noting for T1.2: in expression position `FixCyclicStructReference` also
    claims that diagnostic. This rule's `priority: 100` wins, which is the
    contention docs/20 says must be deliberate — here it happens to be.
  - [x] ~~**2 `:wrong_phase`**~~ **DONE.** `NoCryptoHashPipeSwappedArgs` and
    `NoHallucinatedEtsKeytypeOption` are re-homed to Pattern. The premise was
    re-run rather than reused, and it held exactly: compiling the documented
    shape (the call in a `def` body) yields **zero** diagnostics and
    `compiles?/1 == true`, so no semantic rule could claim anything — while the
    same call in a module attribute is compile-time-evaluated and does produce
    the runtime `ArgumentError` as a `severity: :error` diagnostic that each
    rule wins. A green-making fixture was therefore constructible and would have
    been a lie. Both rules are now pure AST rules; the Pattern round is
    reachable for them because that source *compiles*, which is the precondition
    `pattern.ex` checks before running at all.

    **Correction to this item's own claim: `fix/2` did not transplant
    unchanged.** Semantic's `fix(source, diagnostic)` returns a whole new source
    string; Pattern's `fix_patches(ast, opts)` returns byte ranges. The
    *transformations* transplanted; the interface did not, and the difference
    was not cosmetic — see T5.10, a shared-helper defect that only appeared
    because of it. Both rules also gained the `check/2` half they never had:
    the Semantic versions keyed on a message, so their scope predicate lived in
    `match?/1` on the *diagnostic*. In Pattern, `check/2` and `fix_patches/2`
    now share one literal predicate, which is also what
    `test/corpus/scope_parity_test.exs` requires.

    Both scan **clean over the whole 20,076-file corpus** (`--only-rule`, 0 live
    / 0 accepted each), so neither needs a snapshot re-pin nor a C13 budget
    line. Three positive controls, all seen red: the T5.10 defect put back
    (3 of 7 fix tests red, showing both of its faces); the crypto rule's
    `check/2` disabled (the witness gate names it, with the ledger empty and
    "Adding it to @ledger is NOT one of the options"); and one paid-down entry
    left on the ledger (the graduation test fires, "now witness … Remove them").
- [x] ~~**T5.10 [C] The AST differ patches a bare list one column inside its
  `[`.**~~ **DONE — see the resolution at the end of this item.** Found while
  doing T5.9, and it is a defect in the *shared helper*, not
  in a rule — verified with no credence rule involved. Both public entry points
  (`RuleHelpers.patches_from_ast_transform/3` and `patches_from_postwalk/2`) fed
  a transform that drops one element from `call(:name, [:a, :b, :c])` emit:

      range : %Sourceror.Range{start: [line: 3, column: 18], end: [line: 3, column: 28]}
      change: [:a, :c]
      applied: call(:name, [[:a, :c]])

  The `[` is at column 17. A literal list is `{:__block__, meta, [list]}` and
  **only the wrapper carries the bracket positions** — `line`/`column` for `[`,
  `closing` for `]`. `diff_patches/2`'s scalar clause
  (`lib/rule_helpers.ex:646-655`) stops at the wrapper only when the wrapped
  value is neither a tuple nor a list; for a list it recurses to the bare list,
  whose range is bracket-*exclusive* on both sides, while
  `Sourceror.to_string/1` renders the replacement bracket-*inclusive*. So the
  brackets are counted twice.

  **Why nothing caught it.** `[[:a, :c]]` parses and preserves every comment, so
  `apply_rule_fix_with_status/3`'s safety invariants pass it through. In T5.9 the
  same defect hit two fixtures of one rule and the invariants rejected *one* of
  them (`:patch_rejected`, silently) and shipped the other — the corrupting case
  is the one that survives, because a nested list is more likely to parse than a
  stranded delimiter is.

  **Scope is unmeasured, and that is the honest statement.** The suite is green
  at 9,861 tests, so no *shipped* rule hits it in its own tests or on the corpus
  today. It is a live trap for the next rule that edits a list literal — which
  the harness's weak models will write. Repair: extend the wrapper clause to
  patch at the wrapper's range when its single child is a list that changed.
  Positive control is already written: the perturbation in
  `test/pattern/no_hallucinated_ets_keytype_option_fix_test.exs` reproduces it.
  Before landing, re-run the full suite — this helper is under all 157 Pattern
  rules, so a range change there is a population-wide behaviour change.

  **Resolution.** Reproduced first, with no rule involved: the `[` is at column
  17 and the patch came out at 18, through **all three** public entry points
  (`patches_from_diff/2` is a third the item did not name). The repair is one
  clause in `diff_patches_structural/2`, ahead of the generic same-arity
  recursion: a `:__block__` wrapping a list recurses element-wise **only while
  the lengths match** — that path is the tight, layout-preserving one and had to
  keep working — and otherwise patches at the *wrapper's* bracket-inclusive
  range. Writing the discriminator that way also caught two shapes the item's
  one-line repair would have missed: emptying a list (`[:a]` → `[]`, which the
  defect rendered `[[]]`) and replacing a list with a non-list (which stranded
  the brackets as `[opts]`).

  **The item was right about the rules and wrong about the helper's own
  coverage.** `RuleHelpers` — under all 157 Pattern rules — had no test file at
  all, which is the `SourceMask` gap of T3.10 repeating one day later in a
  module one layer down. `test/rule_helpers_ast_diff_test.exs` now exists: 12
  tests, all three entry points, plus the `rewrap_list/2` idiom the rules
  actually use, and a property asserting the patched source *parses to the
  transform's own tree* rather than matching an expected string. Positive
  control: reverting the fix reddens **8 of the 12**, and the 4 that stay green
  are the ones that must — notably "the double-wrapped output parses", which is
  the test of *why the safety invariants missed this*. Full suite re-run as the
  item required: **9,873 tests + 6 properties, 0 failures**.

  **One sibling found while probing, deliberately not repaired.** An
  *unbracketed* trailing keyword list (`call(:name, a: 1, b: 2)`) has a
  correctly-synthesized range, but `Sourceror.to_string/1` still renders it
  bracket-inclusive, so an element removal *inserts* brackets:
  `call(:name, [a: 1])`. That is layout-only, not corruption — verified to parse
  and to have an identical meta-stripped tree — so it is pinned as a test rather
  than changed, precisely so the next reader can tell it apart from T5.10
  instead of rediscovering it and assuming a regression.

- [ ] **T5.8 [C] Rewrite docs/17's ranked build list** — 0 of 12 cluster
  narratives survived adversarial refutation; the honest net product of the
  143 is "~6 rules to build, 2 lines to widen" (docs/18 §5). Rebuild specs
  live in the JSON's `action` fields (17 rebuild-later + the amended
  catalogue entries). Produce the short, verified list; the 56 banked
  observations stay banked.

### Tier 6 — Phase 9: the next run (runbook, ledger-corrected)

Do not start unattended. Prerequisites in order:

1. T0.1/T0.2 (push + PR merged) → reset sister `evolution` onto the new
   `main`. **Until that reset, none of the new credence gates bind the Gate**
   — the Gate runs the *clone's* suite, and the sister tree today contains
   none of the **five** new meta-gate files (verified 2026-08-16 —
   `pipeline_witness`, `dispatch_contention`, `self_corruption`, `idempotency`,
   `rule_helpers_ast_diff`; this line said "three" while two more had landed,
   so a reader ticking off three would have under-verified the reset).
2. **Archive `var/run/logs` first** — `cev.reset` deletes them
   (`cp -r var/run/logs var/archive/run-2026-07-06/`).
3. Repoint the clone: `CEV_CREDENCE_CLONE=/home/kamil/projects/credence_evolution`
   (config.exs:168's commented example is a stale path from another machine;
   the *default* `../credence` points at the accepting repo — wrong for runs).
4. Land minimum in-loop gates first: T1 (harness half), T4.2, T4.3; strongly
   recommended T2.1–T2.3.
5. **Re-queue list (ledger:940-971 supersedes docs/16:772-775):** diverged — 8
   now (1+18 merged, 7, 106, 107, 162, 164, 205), 3 more after T3.4 lands
   (31, 185, 33), 2 DROP (12 superseded; **105 stays out — it is the probe's
   positive control**); four of the re-queues collapse to one-line
   `undefined_function.ex` table rows. Escalated — 2, 6 (after T4.5), 100 &
   119 (after T4.5's failure-tail fix), 134 (already fixed, `958f241`), 144,
   169 (after refusal triage), 225 (after T3.5), 95 (after T4.2); row 199 is
   the run's one ACCEPT with a named one-predicate narrowing to apply by
   hand. Classifier-error rows 1/23/125/138/139/141/203/227 unblock after
   T3.2. Plus the 105 remaining pass-5 rows (exact: 230 tasks − 125 distinct
   completed).
6. Infra: the 26-row transient tail (11 classifier timeouts, 7 `:closed`, 5
   HTTP 429, 3 implementer kills) — raise Mimo quota or add backoff headroom.
7. `mix cev.preflight` green (with T4.1 landed, it also enforces the mode
   file); flip `STATUS.md` to PRODUCING deliberately.

---

## Part III — State of record (what is done, verified)

Landed and verified this cycle (gate files + positive controls checked by the
research pass; suite green 8,275 + 6 properties corpus-free AND 1,501 corpus
tests at HEAD `958f241`; zero compile warnings):

| Item | Commit | Gate/evidence |
|---|---|---|
| C1 + E9 + stdlib sentinel | `69aa2ec` | battery probe seen red pre-fix |
| C2.1 (4 dimensions) | `5dc7cca` | `equivalence_inputs_test.exs` traps demonstrated |
| C2.2 dimension gate | `3ef1b87` | flagged 2 live rules incl. 1 shipped bug, fixed same commit |
| C3 syntax round guards | `636468d` | `syntax_round_safety_test.exs` red-driving cases |
| C4 semantic pass-revert | `f98c88d` | culprit attribution asserted exactly |
| C5 patch-rejected trace | `7fc6cc0` | 2 broken fixture rules committed red |
| C6 crash isolation (half) | `9d70bab` | 2-of-4 red with isolation removed |
| C8 ordering policy | `c338c67` | docs/20 (gap recorded: no ordering test — T1.2) |
| C13 findings budget | `19f9631` | GREEN-0 + 5 perturbations, exact-invariant attribution |
| C14 DSL static scan | `8b5280e` | GREEN-0 + 4 perturbations; 5 false positives hand-removed |
| C17 standard + STATUS | `b6c3134` | docs/19; reqs 1–5 + 8 gated |
| P1+P2 corpus speed | `1e6e8c6` | A/B verdict parity, honest recalibration |
| P3 scoped scans (+P4-substitute) | `6bd2b05` | 11.6 s vs 234 s; scope-keyed cache poisoning tests |
| Phase-5 defect trio | `958f241` | 134 was an emitter bug not a rule bug; 90/65 six shapes; 69 declined |
| H12 sidecar | `60ce2c4` (pushed) | — |
| H13 + P5 | `96865e7` (pushed) | — |
| H14 push breaker | `6f776fe` (pushed) | — |
| H15 dead-code sweep | `9cffbba` (pushed) | — |
| H9 (Gate half) + LD2 backstop | `fb3bc2a` | 15 gate tests; row-105 guard explicit |
| H16 doc split (IMPROVEMENTS = spec) | `c2b0d95` | — |

Landed **after** this file was written (2026-07-28, same day), all with positive
controls seen red on purpose. Suites green at each landing; at the last of them
(`f521138`) — **8,374 tests + 6 properties corpus-free, 1,501 corpus, zero
compile warnings**:

| Item | Commit | Gate/evidence |
|---|---|---|
| T1.3 C2.2 vacuity block | `070f090` | 3 controls; the two gates stay GREEN under the collapse, which *is* the vacuity |
| T3.1 compiling-source errors + C4 hole | `c691362` | 2 controls; "7 dead rules" refuted to 1 |
| T3.2 `:no_op` trace (credence) | `7708aef` | 2 controls; Semantic mislabel `{rule, 1}` included |
| T3.2 AppliedRules vocabulary (harness) | `7b6e2c6` | control: old regex drops 4 of 5 outcomes |
| **T1 pipeline-witness gate** | `2f34640` | 4 controls, 2 of them real G1/G2 catches in the live tree |
| T3.7 the last two raw-byte syntax fixes | `e81985e` | 22 controls, 22/22 red pre-fix; 4 defect shapes found beyond the 2 recorded |
| T3.7 (cont.) `FixDivRem` per-line masking | `8169601` | 4 controls, 3 red; the 4th green on purpose — it pins the analyze/fix disagreement |
| **the self-corruption oracle + gate** | `b41af7b` | 5 controls; control 1 is the real `8169601` defect put back and caught |
| T0.2 closed as superseded; docs pass | `1cb7bff` · `bff6e83` · `f046dca` | `f046dca` records a commit message that claimed a repair it had not made |
| T3.10 — 2 of 11 (`fix_truncated_binary_close`, `prefer_cond_do_keyword`) | `becd59b` | 12 controls, 11 red; two different repairs, one of them not masking |
| T3.10 — 3 of 11 (`no_doc_with_do_block`) + `SourceMask` gets tests | `643435a` | 4 controls red; `self_contained?/2` extracted; 21 tests for a module that had none |
| **T3.10a — `no_else_if` corrupts valid parsing code** | `f521138` | 5 experiments run; the rule stays on the ledger *on purpose* |
| T3.8 — `FixMalformedSpec` re-homed Syntax→Semantic | `e549bd0` | the ported Issue kept its author-chosen atom; only Syntax attributes that way |
| T3.8 — `FixWithElseBareValue` re-keyed, not retired | `3cdbe14` | `fix/2` was correct all along; the rule matched a message 1.20.2 never emits |
| T5.9 — 4 `:dep_gated` + 2 `:no_fixture` | `f32e315` · `f895bee` | the 4 were never broken; 1 of the 2 needed a fix, not a fixture |
| **T5.9 — the last 2, `:wrong_phase` → Pattern; the T1 ledger is EMPTY** | `6d72130` | 3 controls red; premise re-run (0 diagnostics in a `def` body); corpus clean 0/20,076 both |
| T5.10 — the AST differ double-counted a bare list's brackets | `8b870b5` | 4 controls; `RuleHelpers` had no test file at all until this |
| **T3.10 — 6 more rules (10 of 11 paid down)** | `a9ad691` | 32 of 163 red with the six reverted; a live non-self-corruption defect fell out of one conversion |
| T3.10a steps 1–3 — the sibling absorbs `else if` | `f23722f` | 2 separate controls (widen: 5 red; discriminator alone: exactly 1); `elsif`/`elif` output byte-identical across the widen |
| **T3.10a step 4 — `no_else_if` retired; the ledger is EMPTY** | `4e9d16d` | the gate's vacuity check moved from the result to the machinery — 3 synthetic rules, valid at ledger size zero |
| **D11a — `no_remote_function_in_guard` closed; its sound half ships** | *this commit* | the pattern-move repair only, gated on a bare-variable parameter — the hole docs/18 said the proposed containment check leaves open, executed |
| **D11a — `fix_mixed_required_optional_map_keys`** | *this commit* | arrow-ify beats move-last (same map, local edit); the disposition's own decline list would have rejected the field sample; 0 of 330 lib files altered |
| **D11a — the `when`-guard pair ships as ONE rule** | *this commit* | two rules measured to be impossible (`for THEN def` → `:rolled_back`); 3 docs/18 corrections executed; the byte/grapheme drift that had it inert on any non-ASCII file |

Deliberately **not** done, with reasons on record: P4-as-specced on-disk AST
cache (mooted at 11.6 s scoped scans); P6 (docs/13's own "only if P1–P4 leave a
bottleneck"); K-consecutive-NO_ACTION skip (declined in H8's design — a
sampling-noise NO_ACTION must not become a permanent blind spot); hard-gate
verdict suppression (both H8 and LD4 are advisory *on purpose* — a hard gate
converts a later real regression into an unreportable one); retrofitting
priorities onto 275 rules (docs/20 — an unexamined guess is not better than an
unexamined default); **converting `no_else_if` to `SourceMask`** (T3.10a — it
clears the ledger entry, verified, and would turn the gate green over four
executed corruption modes the entry is the only flag for).
