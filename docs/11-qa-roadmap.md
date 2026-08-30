# 08 — Quality-Assurance Roadmap

> **📜 SUPERSEDED (banner added 2026-07-28).** This pre-docs/12 roadmap was
> folded into the C-items (its §1 ≈ C2, its §3 ≈ C18) and executed from there.
> Open work is tracked in `docs/22-remaining-work.md` only. Kept for the
> research citations.

How Credence can raise its correctness guarantees and test rigor, grounded in
compiler-verification and refactoring-engine research. Scope: **behaviour-preservation
verification** of the auto-fixes and **corpus / test methodology**. Benchmarked against
cross-language refactoring tools and academic/formal-methods work.

> Method note: the external claims below were gathered by a multi-source web research
> pass and adversarially fact-checked (24 of 25 candidate claims passed 3-0
> verification; all sources are primary/peer-reviewed). Citations are in
> [References](#references). The mapping onto Credence is ours.

---

## TL;DR

The literature describes the architecture Credence **already has** — and points at
exactly where this project's behaviour-preservation bugs come from.

- **Keep the spine.** The gold-standard pattern for a safe auto-fixer is *translation
  validation*: don't prove the rewriter correct — check each rewrite and, when you can't
  establish equivalence, **return the source unchanged**. That is Credence's
  fire-on-a-provable-safe-core / otherwise-no-action design, and the `assumptions`
  switches (`:strict` = every-input bar) are a clean encoding of it.
- **There is no silver bullet.** You *cannot* automatically detect all behaviour-change
  bugs (Rice's theorem). The goal is layered defence, not one perfect oracle.
- **Small fixed inputs hide divergences.** This is the recurring pitfall — and the
  direct cause of the bugs this project keeps finding by hand (e.g. the `Map.keys`
  vs direct-`Enum` order divergence only shows on maps with **>32 keys**; a
  `length(x)` rewrite only diverges on non-list `x`). Fixed small test maps mask both.

The improvements below are ranked by value/effort.

---

## 1. Make the equivalence harness a property-based differential oracle  ⭐ highest value

**Today.** `docs/07` compiles the before/after module and runs the function over **fixed**
input sets (`term_lists`, `signed_integers`, `unicode_strings`, `stability_lists`, …).

**The technique.** Generate inputs, run old vs new, flag any divergence, and report a
counterexample only when one concretely exists — this is exactly SafeRefactor and
**EquivcheckEr** [1, 2]. Comparison is on *runtime behaviour*, not syntax.

**Do.** Wire `StreamData` into the harness and bias generators toward the edges the bar
cares about:
- **maps with >32 keys** (HAMT enumeration order — would auto-catch `no_map_keys_enum_lookup`);
- improper lists, empty lists, and **non-lists** (raise-vs-`false` — the `length/1` class);
- negative indices, large inputs, duplicate keys, tied sort keys (stability).

This converts "we eyeballed it on a 3-key map" into "we asserted `before == after` over
thousands of adversarial inputs." It would have caught both findings from the
2026-06-17 corpus audit automatically.

**Caveat.** Dynamic generation is incomplete (see §6) — it complements, never replaces,
the static safe-core. And `before == after` comparison needs a canonical normal form
(§5, §7-Q4).

## 2. Close the analyze-only corpus gap with a *compile* oracle  ⭐ cheap, high yield

**Today.** The over-fire snapshot (`test/corpus/over_firing_test.exs`) is **analyze-only** —
it pins which lines get flagged and never applies a fix. The 2026-06-17 `fix_safety_test.exs`
(comment-loss, var-mangling, over-reach) closed part of that gap with metamorphic invariants.

**The technique.** The single highest-yield oracle in the refactoring-engine study was
`DoesNotCompile` — "does the transformed code still compile?" — which revealed *the most*
bugs in one mainstream engine [3].

**Do.** Add a corpus gate that applies each accepted finding's fix and checks the result
re-parses / compiles (`Code.string_to_quoted`). This catches the whole stranded-token
class (`"x"end`, the spaced-operator `)` bug, unclosed-delimiter regressions) continuously,
not by hand.

## 3. Mutation-test the rules themselves

**The gap.** Your fix-safety tests are only as good as their power to *catch a bad fix* —
and nothing currently measures that. (This was the one thin area in the research: no
published recipe exists for mutating a linter's own fix logic.)

**Do.** Mutate a rule's fix/check logic (flip a guard, drop a narrowing, swap a pattern)
and assert the equivalence + corpus tests **kill the mutant**; survivors mean weak tests.
Elixir tooling: `muzak` / `mutate`. This is the meta-QA that tells you whether the guards
added over time actually have teeth.

## 4. A shared differential-precondition / scope library

**Today.** Every rule hand-rolls its safe core (intentionally — see
`rules-stay-self-contained`). Some safety concerns are cross-cutting and re-derived per rule.

**The technique.** *Differential precondition checking* is a reusable, language-independent,
**linear-time** necessary-condition check: verify a rewrite preserves *name binding* and
*control flow* by diffing before/after, instead of per-refactoring precondition lists [4].
PEQcheck adds the localization: only variables **read-before-written / live-after the
changed segment** need to match; read-only variables can be shared [5].

**Do.** Factor a shared read/write-var + binding-preservation helper. It would catch the
variable-capture / scope class (`__x` mangling, `no_redundant_assignment`,
`no_underscore_in_expression`, `prefer_guard_over_if`) **uniformly** rather than one rule
at a time. (This is the rare case where a shared helper is justified: it serves a whole
class of rules.)

## 5. Bounded-exhaustive small-program generation  (later, higher effort)

**The technique.** JDolly enumerates *all* programs in a bounded scope (no randomness) and
differential-tests them — finding 120 unique bugs across 153,444 transformations that
purely random generation misses [1].

**Do.** An Elixir analog: generate small modules over each rule's trigger shapes, apply
the fix, and run compile + equivalence checks. Systematically surfaces over-firing and
behaviour changes. Start narrow (e.g. the `length`/`case`/`Map.keys` shapes) to avoid
state-space explosion.

---

## 6. Pitfalls the research confirms Credence has already hit

- **AST comparison is "approximate."** Daniel/Dig normalize ASTs (sort members) before
  comparing and warn it is inexact [3]. Credence has lived this — comment/`:line`
  metadata, formatter idempotence, Sourceror range quirks. Define a **canonical normal
  form** once (`mix format` + strip layout metadata) that ignores cosmetic diffs but not
  real ones, and reuse it everywhere (§7-Q4).
- **Golden/snapshot tests give false confidence.** The analyze-only snapshot is the exact
  trap; keep the fix-execution layer as the real gate (§2).
- **Testing is fundamentally incomplete (Rice's theorem).** Even comprehensive suites miss
  subtle semantic changes [6]. So dynamic oracles **complement, never replace** the static
  safe-core proof. Credence's "prove the safe core, then corpus-test" layering is exactly
  the right ordering.

---

## 7. Research agenda (the verified open questions)

1. **An Elixir/BEAM equivalence checker.** `EquivcheckEr` already does repo-scope,
   unchanged-signature, property-based before/after equivalence **for Erlang** [2]. Elixir
   compiles to BEAM / Core Erlang, from the same research group's lineage. Highest-leverage
   lead: a potential off-the-shelf per-rewrite oracle for the corpus pipeline. Open issues:
   macros, side effects, non-determinism.
2. **A cheap static source-safety checker.** CompCert's relaxation lets a fix soundly
   diverge on inputs that *already crash* — but **only if it can prove source-safety**
   (`Safe(S)`) [7]. An ad-hoc fixer usually cannot, which is precisely why
   `integer-is-even`, `div-for-float-division`, `sort-comparator→sort_by`, and the
   `length`-on-unprovable-list cases are rejected or narrowed. A cheap "does not raise on
   the relevant input domain" checker would *license* more aggressive (still sound) rules;
   without it, conservative abstention stays the correct default.
3. **A mutation-testing recipe for the rules** (§3) — undefined in the literature; Credence
   would be defining it.
4. **The canonical Elixir AST normal form** for round-trip / differential comparison —
   what form neither misses real behaviour changes nor flags cosmetic ones (§6).

---

## How this maps to what already exists

| Research concept | Credence mechanism today | Gap / next step |
|---|---|---|
| Translation validation (check each rewrite, abstain on doubt) | fire-on-safe-core, otherwise no-action | — (keep) |
| `Safe(S)` relaxation: diverge only where source already crashes | narrow/reject rules that change crash-vs-value | static source-safety checker (Q2) |
| Behaviour preservation = forward simulation over observable behaviours | "same result for every input" bar; `:strict` assumptions | state the bar in this vocabulary in CONTRIBUTING |
| Differential / round-trip dynamic oracle | `docs/07` equivalence harness (fixed inputs) | property-based + adversarial inputs (§1) |
| `DoesNotCompile` oracle | — | compile-the-fixed-corpus gate (§2) |
| Mutation testing of the checker | — | §3 |
| Differential precondition / localized equivalence | per-rule hand-rolled safe cores | shared scope/binding helper (§4) |
| Bounded-exhaustive generation | curated fixtures + real corpus | §5 |
| AST-normalized comparison (approximate) | Sourceror + `mix format` (ad hoc) | canonical normal form (Q4) |

---

## References

1. SafeRefactor / JDolly — Soares, Gheyi, Massoni et al., *Making Program Refactoring
   Safer* / *Automated Behavioral Testing of Refactoring Engines*, IEEE TSE.
   <https://www.microsoft.com/en-us/research/wp-content/uploads/2020/08/tse12.pdf>
2. EquivcheckEr — Seres, Horpácsi, Thompson, *Equivalence checking of Erlang refactorings*,
   ACM SIGPLAN Erlang Workshop 2024. <https://kar.kent.ac.uk/107137/>
3. Daniel, Dig, Garcia, Marinov, *Automated Testing of Refactoring Engines*,
   ESEC/FSE 2007 (differential + inverse round-trip oracles; AST-normalized comparison).
   <http://dig.cs.illinois.edu/papers/AutomatedTestingOfRefactoringEngines.pdf>
4. Overbey, Johnson, Hafiz, *Differential Precondition Checking*, Automated Software
   Engineering 2016 (ASE 2011). <https://link.springer.com/article/10.1007/s10515-014-0176-9>
5. Jakobs, *PEQcheck: Localized and Context-aware Checking of Functional Equivalence*, 2021.
   <https://arxiv.org/pdf/2101.09042>
6. *Evaluating Small Language Models in Detecting Refactoring Bugs*, 2025 (testing
   incompleteness). <https://arxiv.org/html/2502.18454v1>
7. Leroy, *Formal verification of a realistic compiler* (CompCert), JAR 2009 — translation
   validation, safe-source relaxation, simulation relations.
   <https://arxiv.org/pdf/0902.2137>
8. Necula, *Translation Validation for an Optimizing Compiler*, PLDI 2000.
   <https://dl.acm.org/doi/10.1145/349299.349314>
9. Horpácsi, Kőszegi, Thompson, *Towards Trustworthy Refactoring in Erlang*, VPT 2016
   (conditional rewrite rules verified schematically). <https://arxiv.org/abs/1607.02228>
10. OpenRewrite — recipe testing practice. <https://docs.openrewrite.org/authoring-recipes/recipe-testing>
11. Semgrep — testing autofix behaviour of SAST rules.
    <https://semgrep.dev/blog/2022/testing-autofix-behavior-of-sast-rules/>

**Refuted (kept for honesty):** the claim that *all* refactoring bugs can be detected
automatically / *all* Java behavioural changes caught by SafeRefactor failed verification
(1-2). Treat dynamic oracles as confidence-raising, not certifying.
