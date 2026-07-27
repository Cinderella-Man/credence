# 15 — Hand-off index: the 2026-07-11 investigation, complete map

**Purpose:** single entry point for whoever picks this work up. One
coordinated session on 2026-07-11 investigated Credence + the evolution
harness end-to-end — architecture research, a rule-quality audit, prior-art
survey, improvement proposals for both repos, a test-suite performance
investigation, and an adversarial validation pass that prototyped or
empirically tested every load-bearing claim. Everything produced is listed
here; nothing of substance lives outside these files.

---

## 1. Document map (read in this order)

| # | Document | What it is |
|---|---|---|
| 1 | [`docs/research/README.md`](research/README.md) | Index + provenance of the four raw research reports (below) |
| 2 | [`docs/research/credence-internals.md`](research/credence-internals.md) | Credence pipeline/QA deep-dive: mechanics of all three rounds, compile counts per fix, patch application, DSL guard, meta-gates, equivalence harness, corpus layers, maintainer tools, docs/01–11 gap table, 13 pipeline weaknesses (all cited file:line) |
| 3 | [`../../credence-evolution-harness/docs/research/harness-internals.md`](../../credence-evolution-harness/docs/research/harness-internals.md) | Harness deep-dive: the full rule-gen spine with **verbatim Classify and Implement-seed prompts**, gate mechanics, ops, ADRs, test-coverage gaps, 18-point weakness/signal-loss map |
| 4 | [`docs/research/rule-quality-audit.md`](research/rule-quality-audit.md) | Audit of all 146 pattern rules: inventory, overlap clusters, git archaeology (59% harness-born; 105 `followup —` rejects; DSL retrofit timeline), 12-rule deep critique. **Read its correction header first — two of its three headline defects were refuted.** |
| 5 | [`docs/research/prior-art.md`](research/prior-art.md) | Transferable techniques from Getafix/RuboCop/ESLint/Semgrep/Tricorder etc., ranked top-10 |
| 6 | [`docs/12-improvement-proposals.md`](12-improvement-proposals.md) | **Credence proposals C1–C18**: verified defect fixes, equivalence-oracle hardening, round-safety parity, fixpoint/ordering, performance, hygiene, versioned Rule Standard + semantic-mutant metric (from the dataset repo's QA machinery) |
| 7 | [`docs/13-test-suite-performance.md`](13-test-suite-performance.md) | **Performance investigation P1–P7**: measured cost structure of the ~20k-file corpus suite; parallelization, sweep-sharing, rule-scoped Gate scans, AST cache; Gate ~8.5 min → ~20–40 s end state |
| 8 | [`../../credence-evolution-harness/docs/IMPROVEMENTS.md`](../../credence-evolution-harness/docs/IMPROVEMENTS.md) | **Harness proposals H1–H19** + two addenda (dataset-repo adoptions; Gate-latency cross-ref): executable oracles, Gate rigor, novelty/memory, measurement/provenance, ops hygiene |
| 9 | [`docs/14-proposal-scrutiny.md`](14-proposal-scrutiny.md) | **Adversarial validation** of 6–8: ten experiments (E1–E9), per-proposal verdicts (upheld/revised/refuted), and **Appendices A–C with full reproduction detail** — environment, every script verbatim, every raw output |
| 10 | [`docs/16-evolution-acceptance-and-improvement-plan.md`](16-evolution-acceptance-and-improvement-plan.md) | **The single execution plan** (Phases 0–9). Has a `START HERE` block at the top with the current next actions — read that first |
| 11 | [`docs/17-failure-mode-catalogue.md`](17-failure-mode-catalogue.md) | **What the 143 rejected rules taught us.** 137/140 encode a real defect, verified by execution; 56 failure modes nothing catches; ranked "what is worth building" list |
| 12 | [`docs/18-final-143-disposition.md`](18-final-143-disposition.md) | **Per-rule verdict for all 143 rejected rules** + cross-rule reconciliation (deferral chains, contested dispatch slots, corrections) |
| 13 | This file | Map + actionable state |

Related but separate: the dataset repo's own `STATUS.md` + `docs/12` (its
Quality Standard S1–S12 and improvement-round protocol) — the template for
credence's proposed C17.

## 2. Verified defects and confirmed facts (actionable now)

Everything here was **confirmed by execution**, not reasoning (details:
docs/14 appendix C):

1. **`NoSortThenAt` — live behaviour bug.** Its `asc+at(-1)` and
   `desc+at(0)` mappings rewrite to `Enum.max(c, fn -> nil end)`, which picks
   the *first* maximal; the original picks the *last*. Diverges on
   `[1, 1.0]` (`1.0` vs `1`). **Exact repair:** strict sorter —
   `Enum.max(c, &>/2, fn -> nil end)` — proven `===`-identical over the
   complete int/float divergence class (65/65 lists; min directions already
   agree). File: `lib/pattern/no_sort_then_at.ex` (mappings around `:104-132`,
   `replacement_call`).
2. **`NoSortForTopK` — same bug, second rule** (found by the E1 battery
   probe): its `sort |> reverse |> at(0)` → `Enum.max` mapping. Same repair
   shape.
3. **`no_sort_then_reverse` / `no_double_sort_same_list` are SAFE** on Elixir
   1.20.2 (`:desc` ≡ reverse-of-ascending on ties, 625-list brute force) —
   but the equivalence rests on undocumented stdlib tie behaviour: add the
   **sentinel test** (`Enum.sort([1, 1.0], :desc) === [1.0, 1]`) so an Elixir
   upgrade can't silently break them.
4. **The equivalence battery has a one-input hole:** `term_lists()`' only
   mixed-kind entry ties at the *minimum*. Adding `[1.0, 1]` + `[1, 2, 2.0]`
   is what exposes defects 1–2 (docs/12 C1/C2.1). Landing those entries turns
   the two rules red — fix the rules in the same change.
5. **Gold over-fire reality:** 76/304 dataset golds (25%) carry 124 pattern
   findings across 20 rules (histogram in docs/14 C.3). Any gold-based oracle
   must be a snapshot **ratchet**, not a zero-assert. Full gold scan costs
   ~1.1 s. `prefer_erlang_float` (37 findings on hand-written code) is a
   taste-rule candidate for the C13 budget review.
6. **Analyze is per-rule independent** (0 mismatches, 44 files) — the
   rule-scoped Gate scan (docs/13 P3) is sound; scoped-scan cost is
   10–20 ms/file (parse-bound).
7. **`reject_dsl_unfixable` wastes `fix_patches` on clean files** for the 12
   `unsafe_in_dsl` rules (2,878/2,880 possible wasted calls measured; +30% on
   their scans). One-line fix: skip when `check` returned `[]`
   (`lib/pattern.ex:34-41`).
8. **Single-pass non-idempotency exists but is rare and cross-round:** 1/66
   double-fixed golds; mechanism = Pattern rewrite orphans a variable that
   only a second Semantic pass would fix (`001_002_fixed_window_counter_01`).
9. **The Gate's new-rule mutation check is vacuous** (deleting the new module
   makes its test file fail to compile = RED regardless of assertions), but
   neutered-mutant replacements are only needed for the **13
   `mark_equivalence_*` rules + syntax/semantic rules** — for ordinary
   pattern rules the mandatory equivalence precheck already kills both
   mutant classes (measured 7/7).
10. **Novelty is non-blocking in the harness** (`router.ex:119-132`) —
    deterministic dedup is currently off. The sound re-enable is H7 with the
    **span-overlap** residual rule (docs/14 E8 — the covers-rerun variant is
    non-discriminating because fix output is a ruleset fixed point).

## 3. State of the working tree(s) left behind

- **credence:** clean except these untracked docs
  (`docs/12,13,14,15`, `docs/research/*`). Deps fetched, `MIX_ENV=test`
  compiled. `corpus/` (gitignored) holds a warm 6-package sample
  (jason 1.4.5, decimal 3.1.1, plug 1.19.2, tesla 1.20.0, ecto 3.14.0,
  phoenix 1.8.8). Branch `main` @ `fb6473c`.
- **credence-evolution-harness:** clean except untracked
  `docs/IMPROVEMENTS.md` + `docs/research/harness-internals.md`. Not
  runnable as-is here: preflight requires the credence clone on branch
  **`evolution`** with a clean tree (it is on `main`, with the docs above
  untracked), plus Mimo secrets and the local solve endpoint.
- **elixir-sft-dataset:** untouched (one gold was temporarily modified
  during experiment E2b and byte-restored; verified clean).
- All experiment edits to credence lib/test files were reverted; verified
  `git status` clean at the end of every experiment.

## 4. Gotchas the next person must know

1. **Never run plain `mix test` in credence casually** — the corpus modules'
   `setup_all` fetches ~465 hex packages and shallow-clones ~37 large repos
   on first run. Use `mix test --exclude corpus` (13.3 s locally).
2. **Corpus tests can't run partially:** `Corpus.entries()` is compile-time;
   there is no built-in way to scan a subset (docs/13 P3 proposes adding
   one).
3. `mix credence.equiv` **must** run under `MIX_ENV=test`, and returns a
   **vacuous EQUIVALENT on an empty admitted-input set** (multi-var with no
   `--dim`) — see docs/12 C2.4 before relying on it.
4. The scrutiny experiments (docs/14 appendix B) intentionally mutate rule
   files and restore them — if you re-run them, keep the backup/restore
   discipline and check `git status` after.
5. The four research reports are snapshots; where they conflict with
   docs/14, **docs/14 wins** (it is execution-backed). The rule-quality
   audit's §5.1/§5.3 in particular must not be acted on (refuted).
6. Where numbers differ between docs/13 §1 and docs/14 C.4 (8 vs 19 ms/file
   single-rule), that is measured VM-warmth variance — plan with the range.

## 5. Suggested first moves (smallest-risk, highest-certainty first)

1. Commit these docs (also unblocks harness preflight's clean-tree check).
2. Land the verified fixes as one PR: `NoSortThenAt` + `NoSortForTopK`
   strict-sorter repairs, the two battery entries, the stdlib sentinel test,
   and the E9 one-liner (§2 items 1–4, 7). Every piece has an executable
   proof in docs/14.
3. `mix test --only corpus` for the Gate's phase 2 (harness one-liner,
   IMPROVEMENTS addendum) and the syntax/semantic corpus skip.
4. Then follow the sequencing tables in docs/12 §"Suggested sequencing",
   docs/13 §5, and IMPROVEMENTS §"Suggested sequencing" — they were written
   to be executed in order, and docs/14's corrections are already folded into
   the tiers via the header notes.

## 6. Provenance

Produced 2026-07-11 by a coordinated Claude session (Fable 5 coordinator +
four Opus research agents; agent reports preserved under `docs/research/`),
at Kamil's request: investigate both projects, propose improvements to
auto-generated-rule quality, investigate test-suite performance, then
adversarially scrutinize all proposals with prototypes. Machine: 32-scheduler
Linux, Elixir 1.20.2/OTP 29. The `elixir-sft-dataset` sibling repo appeared
mid-session and its QA machinery (versioned standard, semantic mutants,
blind screening, flake ledger) informed the addenda in docs/12 and
IMPROVEMENTS.md.
