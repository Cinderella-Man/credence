# 21 — In-flight ledger

**Purpose:** the answer to "what was being worked on when the session died?"
Per docs/16 Appendix B (*ledgers over memory*), work that is started but not
committed is recorded **here**, in the repo, not in a session's head. Update it
when a batch is launched and when it lands. Delete rows once they are committed.

---

## Incident 2026-07-28 10:36 — OOM, VSCode killed, 8 agents lost

**What happened.** A batch of **eight** concurrent implementation agents was
launched at 10:25 local (`phases-6-8-batch-2`, run `wf_b3251a89-a7a`). Each was
compiling and running Elixir probes in or beside the same tree; one of them
(C18) additionally made a **full clone of the repo and ran a suite in it**. At
10:36 the box ran out of memory: `erl_crash.dump` in the repo root and a second
one in that clone, the editor was killed, and the workflow died `status: killed`
with `result: null` after **17 minutes and 1.2 M tokens**. No agent ever
returned a value, so nothing was integrated.

**Why it was avoidable.** Nothing about eight was necessary. This box has 24
schedulers and ~12 physical cores; the corpus suite alone takes 983 % CPU
(docs/16 Phase 3). Concurrency limit going forward: **3–4 agents, and never two
that compile Elixir in the same tree at once.**

**Recovered.** All eight scratchpads and all eight agent transcripts were copied
out of `/tmp` before it was cleaned:

```
/home/kamil/projects/credence-salvage-2026-07-28/
    b2-<item>/            per-agent working files (the deliverables)
    _agent_transcripts/   agent-*.jsonl — full reasoning, 8 files, ~4 MB
```

This is the second time this program has nearly lost work to a scratchpad
(docs/15 gotcha 7). **A scratchpad is not storage** — the salvage directory is
not either. Anything worth keeping gets committed.

### Safe as of the crash — committed and pushed

`credence` on `evolution_accepted` is clean and pushed through `c338c67`:

| commit | item |
|---|---|
| `7fc6cc0` | C5 (6.1) — surface the silent patch-drop path |
| `5dc7cca` | C2.1 (6.2) — four missing equivalence-battery dimensions |
| `f4d08a8` | Phase 5 — escalation ledger + phantom `redefining module` fix |
| `9d70bab` | C6 (6.2) — per-rule crash isolation |
| `b6c3134` | C17 (6.7) — Rule Standard v1, stratification audit, `STATUS.md` |
| `f98c88d` | C4 (6.3) — semantic per-pass compile-revert with culprit attribution |
| `636468d` | C3 (6.3) — the Syntax round's two guards |
| `3ef1b87` | C2.2 (6.2) — dimension-mapping gate + the live bug it found |
| `6bd2b05` | P3 + P4 (7) — rule-scoped corpus scans + the analysis cache |
| `c338c67` | C8 (6.4) — rule ordering policy (docs/20) |

`credence-evolution-harness` on `main` has `P5+H13` (`96865e7`), `H12`
(`60ce2c4`) pushed, and **three commits unpushed**: `6f776fe` (H14 push-failure
breaker), `9cffbba` (H15 dead Python-translation sweep), `fb3bc2a` (H9 + LD2).
**Push those before anything else touches the harness.**

### Lost as return values, recoverable from the salvage

Six of the eight were close to done — several were writing their *positive
controls*, i.e. the last step — when they were killed. None of their work is in
either repo.

| item | repo | how far it got | salvage artifacts |
|---|---|---|---|
| ~~**C13** whitelist budget gate~~ | credence | **✅ LANDED 2026-07-28** — salvage verified and integrated; see below | — |
| **H8** verdict memory + positive exemplars | harness | 42 tests passing, writing the mutation positive controls | `b2-h8/verdicts.ex`, `classify.ex`, `prompt.ex` (35 K), `verdict_memory_test.exs`, `ctl1–ctl6/` |
| **Gate staged-path dispatch** (Addendum 2 / 8.7) | harness | Gate integration test against a stub `mix` | `b2-gatedispatch/corpus_dispatch.ex`, `corpus_dispatch_test.exs`, `gate_corpus_dispatch_test.exs`, `gate.ex.REFERENCE_ONLY` |
| **LD3 + LD4** test-only-diff policy + known-good list | harness | five modules written, no summary | `b2-ld34/test_only_diff.ex`, `verified_good.ex`, `row_log.ex`, `trace_evidence.ex`, `classify.ex`, `prompt.ex` |
| ~~**C14** DSL-safety static scan~~ | credence | **✅ LANDED 2026-07-28** — salvaged scanner verified, corrected and gated; see below | — |
| ~~**P5 bugs** (3 credence defects)~~ | credence | **✅ LANDED 2026-07-28** — 2 fixed, 1 correctly declined; see below | — |
| **C18** semantic-mutant sweep | credence | early — had just cloned the repo (this is the agent that OOMed) | `b2-c18/mutation.ex`, `sweep.ex`, `credence.mutants.ex` |
| **C7** idempotency gate | credence | earliest — reading docs, one fixture sweep | `b2-c7/fixtures.bin`, `sweep.exs` |

**Treat every salvaged artifact as unverified.** It was written by an agent that
never got to state its own verdict, and in at least one case (P5 bugs) the agent
had just discovered its approach was wrong. Re-derive the claim before trusting
the code.

---

### Salvage recovery log

**C13 — landed.** The salvaged implementation was verified rather than trusted,
and it held up:

- `mix credence.corpus --update-budget` regenerated `accepted_findings_budget.txt`
  **byte-identical** to the agent's copy, so its numbers were reproducible, not
  asserted.
- Its central empirical claim was re-measured independently and is real: the
  distribution has a genuine gap at the cap — the 15th-largest rule holds **122**
  accepted findings and the 16th holds **99**, so a cap of 100 grandfathers
  exactly the 15 rules carrying 74% of the debt and leaves the other 72 firing
  rules compliant with no slack.
- Its load-bearing design decision was checked against the harness rather than
  taken on faith: `--update-snapshot` deliberately does **not** write the budget
  file, because `Cev.Evolve.Corpus.delta/1` uses `--update-snapshot` as a
  read-only probe that saves and restores *only* the snapshot path
  (`lib/cev/evolve/corpus.ex:56-71`). A second file written behind its back
  would be left dirty in the clone and would redden the Gate on the next row.
  Confirmed correct.
- Positive controls: five perturbations plus an unperturbed **GREEN-0** control
  (a runner that reddens everything proves nothing). Each of the five trips
  exactly the invariant it attacks, GREEN-0 passes.

Two documentation defects fell out of doing it, both of the same shape — an audit
row *quoted* rather than measured:

1. **docs/19 row C was wrong.** It read *6,155 accepted findings across 90 rules*
   and was labelled measured 2026-07-28; those are docs/12's figures from
   2026-07-11. The snapshot holds **6,366 across 87 rules** — the row was wrong in
   both directions at once. Corrected, and now backed by a gated file.
2. **docs/19 requirement 4 was listed ungated** although C2.2's
   `equivalence_dimension_meta_test` had landed 80 minutes before docs/19 was
   written. Corrected.

**C14 — landed.** The salvage here was a working scanner and a raw 155-rule
classification, but **no gate test**, and the by-hand cross-check C14's spec
explicitly requires had not happened. Doing that cross-check is what earned its
keep:

- The scanner reproduced its own classification exactly (155 rules; 45
  `:possibly_unsafe`), so it was deterministic.
- But **five of the 45 were false positives of one class**: a matcher for
  `&fun/arity` whose capture `/` was read as division. The scan exempted only a
  *literal integer* arity, so `&fun/arity` with the arity bound to a pattern
  variable — the ordinary way to write it — was flagged, as was Sourceror's
  `{:__block__, _, [1]}` arity wrapper and its meta-elided `{:&, [spec]}` pair.
  Fixed by handling the capture node itself rather than the `/` in isolation:
  once the enclosing `&` is out of view, `{name, meta, ctx}` is indistinguishable
  from a divisor. **45 → 40.**
- The 40 are frozen in the gate's `@unclassified` ledger, split by evidence
  strength: 17 touch a construct `DslGuard` attributes to a real family, 23 are
  flagged only on unattributed constructs. Recording that split matters — a flat
  40 implies 40 equal risks.
- The gate also closes the loop the audit row missed: **101 of the 141
  "unclassified" rules cannot be affected by this class at all.** The work is 40
  rules, not 141.
- Positive controls: GREEN-0 plus four perturbations. The first attempt reddened
  on the *wrong* invariant — a fabricated extra rule file made the rule count
  mismatch, so the vacuity check fired and the gate itself was never exercised.
  Rewritten to the realistic scenario (an existing rule's fix starts building a
  construct), it now trips the intended invariant.
- `mix credence.gen.rule` now emits a deliberate `unsafe_in_dsl/0`, **verified by
  scanning the generator's own output** — a freshly scaffolded rule classifies as
  `:declared`.

**P5 bugs — landed: two fixed, one declined.** The killed agent's last note was
the useful part of the salvage: it had just discovered that `heredoc_value/1`
returns raw source bytes rather than the compiled value, "which changes the fix".
It was right, and that turned out to be half the defect.

- **Row 134 is not a `PreferSigilCharlist` bug**, as the ledger already said and
  docs/16 still didn't. The rule's output is correct; the emitter recording it was
  not. `heredoc/1` spliced raw output into a `"""` heredoc, so `~c"say \"hi\""`
  read back as `~c"say "hi""` — and output containing `#{` was worse than
  corrupted, parsing as an *interpolation* the reader could not see as a string at
  all. Fixed on both sides, because Sourceror parses with `unescape: false`: escape
  on emit so ExUnit reads back the rule's real output, and unescape on read so the
  rule is handed the value the running test passes rather than raw bytes. Those two
  are exact inverses, which is what keeps the task idempotent.
- **`Credence.FixtureHealer` had the same emitter gap** — the ledger flagged it as
  a suspicion and it is now resolved: it **cannot corrupt**, because
  `values_preserved?/2` compares *compiled* values and rejects the write. The cost
  was silent rather than loud — those fixtures were simply never canonicalized.
  Fixed too; zero fixture files changed, so the gap was latent.
- **Row 90/65 (`NoBareNamesInSpec`) fixed, and the boundary was wider than
  recorded.** Six no-op shapes, not three: `|` unions, list, tuple and map type
  terms, the return position, and — beyond the ledger's stated boundary — *any*
  spec carrying a `when` guard, where even a top-level bare argument no-opped
  because `fix_spec_body/2` never unwrapped the guard. This is the worst shape a
  Semantic rule can have: `lib/semantic.ex` records `{rule, 1}` even for a no-op
  and dispatches with `Enum.find`, so the rule consumed the diagnostic, nothing
  else could claim it, and the compile error survived every pass.
- **Row 69 declined, not fixed.** `NoRemoteFunctionInGuard` is not in this repo —
  sister only, already dispositioned *rebuild-later*. docs/16 §6.5 listed it as a
  credence bugfix; that entry is now corrected.

One finding worth carrying: **widening the spec walk introduced a bug, and only
`compiles?/1` caught it.** Annotating a name the `when` guard *binds* produces
`@spec parse(t :: any()) :: map when t: atom()` — which names and binds `t` at
once, and Elixir rejects it. The output text looked entirely reasonable. This is
the fourth time in this program that asserting text instead of meaning hid a
defect (cf. docs/16 §4.6a finding 3); the rule now declines that shape.

### The PRODUCING bar is now met

`STATUS.md` set it as requirements 4, 5 and 8 wired into the meta-gates, the
generator and the harness seed. All three legs are in place (the harness seed
already taught self-classification, `lib/cev/implement/seed.ex:244`).

**The mode file is deliberately still `CATCHING UP`.** The intended mechanism is
that `mix cev.preflight` refuses to start a generation run while it says so —
**note (corrected 2026-07-28): that interlock is documented but not implemented;
nothing in the harness reads STATUS.md yet.** Building it is docs/22 task T4.1.
Either way the flip is the maintainer's call, made on purpose rather than as a
side effect of the last gate landing.

---

## Currently in flight

*(nothing — update this section when work starts, clear it when the work lands)*

*(T3.10a step 4 — retiring `no_else_if` — was on the maintainer's desk for one
turn and has since been decided and landed. The self-corruption ledger is empty.)*

**Everything else that remains — for both repos — is tracked in one place:
[`docs/22-remaining-work.md`](22-remaining-work.md).** The "Next, in order" list
that used to live here moved there (Tiers 0–6); this file stays the incident
record and the in-flight ledger only.

Completed since the salvage table above was written: the deep-evaluation
research pass (`wf_e7db30ca-1fc`, 2026-07-28 — 4 read-only miners + 2
adversarial verifiers, ≤4 concurrent, zero compiles; its findings are docs/22
Part I). The P5-bugs, C13 and C14 rows were landed earlier the same day
(`958f241`, `19f9631`, `8b5280e`).

---

## Session 2026-07-28 (afternoon) — CLOSED, nothing in flight

Everything started in this session is committed. Landed: T0.1 (push), T1.3
(`070f090`), T3.1 (`c691362`), T3.2 credence (`7708aef`) + harness (`7b6e2c6`),
T1 (`2f34640`). Tracker updated in the same pass; open work is docs/22 only.

**Concurrency held, and it worked.** Two research workflows ran, both at **4
read-only agents**, both explicitly forbidden from running `mix`/`elixir`/`iex`
— all compiling stayed in the single foreground shell. No OOM, no crash dump.
The 8-agent incident above was 8 agents *each compiling*; the rule that came out
of it ("max 3–4, never two compiling in one tree") is the one that was followed.

**The methodological finding worth carrying forward.** Read-only agents produced
excellent evidence and two *wrong verdicts*: `NoCryptoHashPipeSwappedArgs` and
`NoHallucinatedEtsKeytypeOption` were both called DEAD from source reading, and
both are reachable — each agent had flagged its own uncertainty and named the
exact one-call check that would settle it, and running those checks overturned
the verdicts. Agents that cannot execute should be asked to name the experiment;
the orchestrator should then run it. Reading is a hypothesis generator.

---

## Session 2026-07-28 (evening) — CLOSED, nothing in flight

Resumed after a VS Code crash. The crash left exactly two artifacts: an
uncommitted `docs/22` edit closing T0.2, and an untracked scratch probe for T1.2
(`test/zz_contention_test.exs`, moved out of the tree — it is exploratory, not a
test). Both dispositions are recorded; nothing else was in flight.

Landed: T0.2 closure (`1cb7bff`), T3.7 (`e81985e`), T3.7-cont `FixDivRem`
(`8169601`), the self-corruption oracle and its gate (`b41af7b`), and this
records pass. New tracker item: **T3.10**, the 11-rule paydown the gate
uncovered.

**The finding worth carrying forward: an unexecuted correction is not more
reliable than the unexecuted claim it replaces.** T3.7 existed *because* a
docs/16 row claimed a repair nobody had made. Writing the repair then found four
more shapes of the same defect that the correction had also missed — sigils,
charlists, heredoc bodies, and trailing comments — because the correction was
written by reading too. Then, with the family declared closed twice over, an
oracle found `FixDivRem` still corrupting heredocs after having been reviewed,
converted, tested, changelogged and shipped as fixed.

**What broke the loop was changing the input, not the effort.** Every previous
pass read the rule and read its tests, which is one act rather than two: the same
person wrote both, so they agree by construction. A rule's own source file is an
input nobody authored to make it pass, and the Rule Standard *guarantees* it is
adversarial — a moduledoc is required to contain the exact byte sequences the
rule rewrites, inside a heredoc, beside English prose naming the operator. One
`fix/1` call per rule found 11 of 45. Generalisation for the harness: when a gate
keeps missing a class, look for an input the author did not choose before writing
a cleverer gate.

**Concurrency held again.** One workflow, 4 read-only agents (3 miners + 1
adversarial verifier), all forbidden `mix`/`elixir`/`iex`; every compile and
every probe ran in the single foreground shell. No OOM.

**And the read-only agents were right to be doubted, in both directions.** The
family sweep *refuted* docs/22's "exactly two rules" scope — correctly, and it is
why T3.10 exists. Its adversarial verifier then caught the sweep in a false
accusation of its own (`NoStringReplaceArityMismatch`, classified as a raw-byte
rewriter from a grep signature; it is AST-based, and the `String.replace` hits
were its own moduledoc prose, since the rule is *about* `String.replace`). Both
agents named experiments instead of running them; the orchestrator ran them, and
the cheapest one — the self-corruption oracle — was worth more than every verdict
either agent offered.

**Continued the same session: T3.10, and one deliberate non-fix.** Three of the
eleven ledgered rules are paid down (`becd59b`, `643435a`), and the useful result
is that all three needed *different* repairs — masking, a parse guard, and
`SourceMask.self_contained?/2`. Applying the family default to
`no_doc_with_do_block` would have been worse than doing nothing: its pattern keys
on the `"` quotes that masking blanks, so on the shadow it matches nothing, ever
— green here, green in its own tests, and silently retired. **A hit from this
oracle says the rule edited bytes that are not code, and nothing more.**

`no_else_if` is on the ledger and is staying there on purpose (`f521138`, docs/22
T3.10a). Running it showed it turns *valid, parsing* nested-`if` source into
output that does not parse, plus three boundary cases that do the same. Masking
its trigger clears the ledger entry — verified — and would turn the gate green
over four executed corruption modes that the entry is the only flag for. Its
sibling `fix_elsif_in_if_chain` is hardened against all six defects, and a third
copy of the same rule was rejected in review for being that sibling's
pre-hardening state, which is exactly what `no_else_if` is. Retiring a live rule
is the maintainer's call, so the sequence and the failure mode (FM-ELSE-IF) are
written down rather than executed.

Two of my own claims were wrong this session and are corrected in place rather
than quietly: `bff6e83`'s message asserted a blockquote repair it had not made
(fixed and recorded in `f046dca`), and `SourceMask`'s comment claimed its blank
byte "cannot take part in a match" — `\S`, `.` and negated classes do match it,
now pinned in a test. The tally that matters is not that they happened but that
both were found the same way as everything else here: by running the thing.

---

## Session 2026-07-28 (late evening) — CLOSED, nothing in flight

Resumed after a VS Code crash. **The crash cost nothing**: the tree was clean and
`origin/evolution_accepted` was already level with `HEAD` (`6d72130`), so there
was no unpushed work and no salvage. Worth stating plainly after five OOMs in one
day — the discipline of committing and pushing per item is what made the crash a
non-event.

Landed and pushed: **T5.10** (`8b870b5`), **T3.10** 6-rule paydown (`a9ad691`),
**T3.10a steps 1–3** (`f23722f`). Suite went 9,861 → **9,923 tests + 6
properties, 0 failures**, run in full before each of the three commits.

**Zero agents, zero workflows, one shell.** Every compile, probe and suite run
was in the single foreground shell. No OOM, no crash dump. The three full-suite
runs cost ~4m10s each and ~38 minutes of CPU — that is the thing that must not be
run concurrently with anything.

**The finding worth carrying: a conversion is a reading nobody has done before,
so budget for it surfacing unrelated bugs.** T3.10 was scoped as "make six rules
literal-aware". Converting `fix_python_augmented_assignment` for that reason
exposed a *different* live defect underneath — its right-hand side ran to the end
of the line, so `count += 1  # note` became `count = count + (1  # note)`, closing
paren inside the comment, output that does not parse. Three of six probe inputs
failed. Nothing in the ledger pointed at it; it fell out of looking at the rule
closely enough to mask it.

**Second: knowing about a failure class is not being guarded against it.**
`no_fn_with_capture` carried a guard *and* a comment explaining that rewriting
non-code content would corrupt it — and the guard only skipped lines starting
with `#`. It protected comments, missed heredocs, and rewrote three sentences of
its own moduledoc from naming the broken form to naming the fixed one. Two more
rules *argued in their moduledocs* that literals were safe, on reasoning true
only by accident of `^`-anchoring, which runs out inside a heredoc. A written
safety argument is a hypothesis like any other.

**Third: one perturbation cannot prove two claims.** T3.10a widens a rule *and*
adds a discriminator. Reverting the widen reddens the five rewrite tests but
leaves every "declines" test green — they pass vacuously against a rule that
never matched `else if`. Only disabling the discriminator alone, with the widen
kept, reddens the valid-nested-`if` decline, and it reddens exactly that one. Two
controls, because there were two things to prove.

Also: `RuleHelpers` — the module under all 157 Pattern rules — had **no test
file at all**, which is the `SourceMask` gap of the previous session repeating
one layer down, one day later. It has one now.

**Left for the maintainer, deliberately: T3.10a step 4** (retire `no_else_if`).
The evidence is executed and written down; deleting a live rule is not this
session's call.

**Continued: T3.10a step 4 — the rule is retired, and the gate that measured it
had to be rebuilt.** `no_else_if` is deleted (rule + two test files) on the
maintainer's decision, taken once steps 1–3 had the evidence executed. Its
behaviour survives as the two `else if` describe blocks in
`fix_elsif_in_if_chain_fix_test.exs`, which say in a comment that they are the
surviving record — deleting a rule is only safe while its behaviour is pinned
somewhere, and that is the somewhere.

**The finding worth carrying: paying a ledger down to empty disarms the gate that
measured it.** The self-corruption gate's vacuity test asserted *"some Syntax rule
still corrupts its own source"*, which is exactly right against a non-empty ledger
and worthless the moment the debt reaches zero — that is the instant when "nobody
corrupts" and "the differ stopped working" become the same observation from
outside. The last entry leaving is precisely when the check protecting you
evaporates, and nothing goes red to tell you. Any ratchet built this way hits this
on its final entry.

The repair is to move the vacuity check from the *result* to the *machinery*:
`SelfCorruption.corrupted_lines/2` is now public, and the gate feeds it a rule
that certainly rewrites its input, one that certainly does not, and one that
raises. Three controls that hold whether or not any real rule is broken —
strictly stronger than what they replaced, and only findable by asking what the
gate would still be worth after the work succeeded.

Suite: 9,911 tests + 6 properties, 0 failures.
