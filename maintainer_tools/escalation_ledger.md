# Escalation ledger — Phase 5

**Date:** 2026-07-27 · **Source:** `credence-evolution-harness/var/run/logs/`
**Scope:** every escalated row, every behaviour-diverged row, every classifier
error, and the run's single switch proposal. 95 decisions.

> Phase 9 step 1 warns that `cev.reset` deletes these logs. This ledger and the
> per-row reasoning below are the durable record; archive `var/run/logs/` before
> the next run regardless.

## Verdict split

| verdict | n | meaning |
|---|---|---|
| **DROP** | 48 | no action; delete the artefacts |
| **RE-QUEUE** | 26 | feed back into the next run |
| **FIX-CREDENCE** | 11 | a real defect in a credence rule |
| **FIX-HARNESS** | 9 | a real defect in the harness |
| **ACCEPT** | 1 | the preserved patch is a true positive |
| **total** | 95 | |

**78 of 95 rows disagree with docs/16 Appendix A** in mechanism, verdict, or both.
Appendix A was written from a survey; these rows were read end to end and their
claims re-executed. Where they differ, this ledger is the later and better-evidenced
account — but Appendix A's *arithmetic* (45/13/52/2, and the 44/6/1/1 split inside
the classifier errors) was verified correct.

---

## Cluster findings

The per-row table is downstream of these. Several rows are individually
uninteresting and collectively decisive.

### escalated 2–78

Ten rows, and only one of them (48) is the simple thing Appendix A says it is. Five systematic defects fall out, four of them harness-side.

**H-A. The Gate cannot tell a crashed `mix test` from a red one (row 2).** `mix test --exclude corpus` died in `Kernel.ParallelCompiler` with `:io.put_chars(:standard_error, …) → :terminated` after 4.7 s, having run zero tests, and the Gate logged `REJECT: :full_suite_red`. The candidate had already passed the mutation gate, and the implementer's own run 4 minutes earlier was 7309/0. Two free discriminators go unused: no `Finished in … tests, … failures` line, and 4.7 s against a ~2 min baseline. This is H9's environmental-failure triage and it should gate on evidence-the-suite-ran, not on exit code.

**H-B. The classifier's minimal repro is never validated against the rule it accuses — and it is the only thing the implementer ever sees (rows 40, 50, 59; the biggest finding in the cluster).** In all three rows the real over-fire is printed *in the same log*, in the solve-phase `[credence_fix] <Rule>: source CHANGED` trace, with exact before/after lines on a real 300-line workspace file. The classifier then writes a hand-reduced `BEFORE`/`AFTER` pair; the workspace file is discarded; the implementer reproduces against the reduction, finds it green, and writes "the rule already handles this correctly" — three times, about a rule that was actively corrupting files. I confirmed row 59's reduction does not reproduce (current pipeline: `NoPythonMultiReturn` returns `[]`; `NoKeywordIfBareInTuple` produces the classifier's own proposed AFTER), and that row 40's real lines *did* still reproduce on credence_evolution HEAD at end-of-run. Fix: derive the accusation mechanically from the `source CHANGED` trace lines and preserve the workspace file as a fixture; if the reduced repro does not make the accused rule fire, fail the row rather than shipping it to an implementer. This also invalidates the "`:no_lib_change` = rule already correct" reading of that whole cluster — at least 3 of the 11 rows were live bugs the harness talked itself out of.

**H-C. Two distinct non-merit failures are reported as merit failures.** Row 6: an implementer session with **zero Edit/Write calls** (25 steps, all Read/Glob/Grep) ended `subtype=success turns=17/80` and the Router reported `gave_up: {:cc_tests_red, left: "foo(bar)", right: "baz(qux)"}` — those are the untouched scaffold placeholders. Row 55: `API Error: Request rejected (429) · quota exhausted` at step 75, mid-`Edit`, also reported as `gave_up: :cc_tests_red`. A null run and a quota kill are both recoverable and neither is evidence about the rule. Add a zero-write detector and route 429/timeout kills to the transient lane (Phase 9.4 capacity work).

**C-A. A live, shipped credence defect kills an entire diagnostic class (row 78).** `RuleHelpers.compile_and_capture/1` tags Elixir 1.19 type-checker failures `{:ok, …}` because `Code.compile_string/2` still returns modules; `Credence.Semantic.analyze/2` and `do_fix_traced/4` then filter that branch to `severity == :warning` and drop every `:error`. Reproduced at HEAD (26d14e6): `analyze` returns `[]` for `unknown key :size for struct …`, and `compiles?/1` returns `true` for source `elixirc` rejects. Seven live semantic rules key on this text and are therefore dead in production. docs/18 identified this and asked for it to be filed against the live repo; it was not among the nine Phase 4 repairs. This is the highest-value item in the cluster and it is not in Appendix A.

**Cross-cutting: nothing records the failure mode of a Gate-rejected rule.** Rows 48, 55, 73 and 6 never entered the docs/18 drain, so their failure modes vanish with the artefacts. Two of the four are worth keeping (row 55's trap_exit-without-EXIT-handler, row 73's discarded `unless` early return — the latter hit all three solve attempts), one is a switch-gated candidate rather than a narrowing, and two (48, plus 73 in its current form) are dead on the premise. Extract before deleting.

**Method note that made the dating possible:** log wall-clock is UTC+2 and `rows.jsonl` `ts` is UTC epoch; matching row 40's `REJECT` at 15:56:08 to ts 1783950968 fixes the offset. That is what lets rows 50/59 (2026-07-08) be placed *before* credence_evolution a7c6985 (07-09, the struct-pipe guard) and row 40 (07-13) *after* all ten `bugfix(over_fire)` commits — i.e. NoPythonMultiReturn's over-fire survived the entire evolution run and was only killed by the Phase 4 acceptance rewrite (17bec10). Worth stating in the ledger: the acceptance drain was load-bearing, not cosmetic.

### escalated 82–137

Ten rows, four verdicts: 5 DROP, 2 RE-QUEUE, 1 FIX-HARNESS, 1 FIX-CREDENCE, 1 DROP-with-FIX-CREDENCE-followup. Five systematic findings, three of them harness defects.

**H-A. The classifier's BUGFIX branch has no spec validation at all.** `Cev.Classify.check_decision/2` (credence-evolution-harness/lib/cev/classify.ex:106-114) checks only that `rule_name` is in the closed set and resolves to a file. The parse gate, the `before` gate and the mandatory-`after` gate are all on the `:potential_new_rule` branch. Consequence, in 3 of my 10 rows: row 95 dispatched an 80-turn Claude Code session on a spec whose PROPOSED_NAME/PHASE/BEFORE/AFTER were each the literal string `===` (the model's placeholder for N/A; `Parser.blank_to_nil/1` passes it through as non-blank); rows 116 and 123 dispatched on specs whose BEFORE and AFTER are byte-identical. All three ended `:no_lib_change` or `mutation_no_effect` because there was nothing to reproduce. Two cheap gates fix the class: reject `:bugfix_rule` when `before == after`, and treat a section body that is only `=` runs as blank. A third would raise the yield a lot: make the classifier quote the verbatim offending LINE from the `credence_fix` trace rather than re-minimizing — row 116's `mutation_no_effect` is precisely a re-minimization (multi-line `if`) that no longer triggers the bug the trace had already printed (single-line `if` inside a `fn` at L294).

**H-B. Implementer give-up reasons report the wrong end of the output.** `lib/cev/implement.ex:66` truncates with `String.slice(failures, 0, 400)` — the HEAD of `mix test`, which is compile warnings — while the LLM path in the same file already has `trim/1` (last 3000 chars). Nothing records the exit code or which of `focused_test/1`'s two `mix test` legs failed. This is why rows 100 and 119 read as "pre-existing warnings" and became docs/16's "suite-noise victims": warnings cannot make `mix test` exit non-zero (no `--warnings-as-errors` in `run_mix_test`, none in either mix.exs), and the warning cited by row 119 (`test/semantic/no_exit_two_args_fix_test.exs:10`, `defp fix(source, message, line \\ 1)` with all four call sites passing 3 args) is still present in credence_evolution today. Row 100's real blocker was a genuine pre-existing failure — the `NoKeywordIfBareInTuple.fix/1` crash — which IS repaired (verified: `Credence.fix/1` on the pipeline fixture now returns cleanly with `applied_rules: []`). Row 119's remains unidentified, and cannot be identified from the log as written.

**H-C. "Rule matched, fix returned IDENTICAL source" is the classifier's favourite BUGFIX trigger and is wrong most of the time.** Rows 82, 95 and 97 are all this shape. Two of the three were rules legitimately declining by design — documented no-ops guarded by `should_report?/2` (FixNimbleCsvDirectParse: no `NimbleCSV.define` in the file, so no target; FixPlugDependencyModuleOrder: already repaired). The one that is a genuine defect is the rule with NO such guard: `Credence.Semantic.UndefinedFunction` matches `undefined function send_resp/2 (…or for it to be imported…)` and returns the source unchanged, and because `Credence.Semantic` dispatches first-match (lib/semantic.ex:191), it consumes the diagnostic and no other rule gets a turn. Two consequences: the C5 patch-drop trace should distinguish "declined (rule exports `should_report?/2`)" from "attempted and failed", which would remove most of the lure; and giving UndefinedFunction a decline guard is a small, real credence improvement.

**C-D. The corpus layer is the only gate that catches over-firing.** Rows 124 and 137 both passed their check, fix, equivalence AND mutation gates and were killed solely by `mix test` on the corpus. Row 124 is the sharper warning: the rule is behaviour-changing *by its own moduledoc* (`for x <- l, do: if(c, do: v)` keeps nils, `for x <- l, c, do: v` drops them — different list lengths) and its equivalence test, written by the same agent, still went green. The agent also added a `@verified_dsl_safe` entry asserting "`for` comprehensions aren't valid DSL expressions", which 2 of its own 35 hits falsify (slugger/lib/slugger.ex:104 defines a `defp` inside the `if`; spark/lib/spark/dsl.ex:584 is a compile-time extension loop). An agent-authored equivalence test and an agent-authored DSL-safety claim are not evidence — both belong on Phase 6.5's C14 worklist.

**C-E. Escaping is a systemic weak spot in credence's own test tooling, not in any rule.** Row 134's headline — recorded in docs/16 as an unfixed `PreferSigilCharlist` bug — is misattributed. The rule's output `~c"say \"hi\""` is correct and parses. The corruption comes from `Mix.Tasks.Credence.FixTests.heredoc/1` (credence/lib/mix/tasks/credence.fix_tests.ex:246), which splices the rule's raw output into a `"""` heredoc without escaping `\` or `#{`; I reproduced the exact give-up strings by calling `fix_file/1` on a scratch copy. It silently corrupts any fix test whose expected output contains a backslash — i.e. exactly the escaping rules, exactly where it matters. Worth checking `Credence.FixtureHealer.heal_dirs/0` (test/support/fixture_healer.ex:40) for the same class: it rewrites every file under test/{pattern,semantic,syntax} in place on every `mix test`, including focused runs, so a bug there mutates hundreds of unrelated test files per invocation.

**Cross-check against docs/16 Appendix A.** Agrees on 6 rows (82, 97, 116, 123, 124, 137), diverges on 4. Rows 100 and 119: the re-queue call is right, the stated root cause (warnings) is not — 100's was a real failure since repaired, 119's is still unknown. Row 134: the named rule is not the buggy component. Row 95: filed as "rule already correct" when the row never had a spec. The `:no_lib_change` cluster is also less homogeneous than A suggests — of my four (82, 95, 97, 123), only 97 is straightforwardly "rule already correct"; 82 is a same-row re-suspicion after its own fix landed, 95 is an empty spec, and 123 reported a genuine corruption that was fixed later at acceptance rather than being correct at the time.

### escalated 144–225

Nine rows, all read end to end, every claim re-verified against the live corpus and the current credence tree (Elixir 1.20.2 / OTP 29). Six findings hold across the cluster rather than per row.

**1. Two of the four "small over-fires" are not over-fires — they are corrupting fixes, and only the corpus caught them.** Row 150's rewrite turns the correct `:counters.new(2, [:write_concurrency])` into `[{:write_concurrency, true}]`, which I verified raises `ArgumentError: 2nd argument: invalid option in list`, and it rewrites `:read_concurrency,` inside a plain `@info_keys` data list. Row 162's fix deletes a live `catch` clause in tesla that maps zlib `{:data_error, _}` to `Tesla.Error`. Both rules had fully green check/fix/equivalence suites and both passed the mutation gate. The corpus gate was the only thing standing between them and `main`, and it caught them by accident of corpus content, not by design. When H8's rejected-over-fire list is seeded, it must carry the *mechanism* per entry, not the rule name — "no `:ets.new/2` scope on a leaf-atom match", "vacuous `nil == nil` guard" — or the same shapes will be re-proposed under new names.

**2. One shared implementation anti-pattern generated three of the four over-fires: the context-free leaf match.** Row 150 matches a bare atom without checking the enclosing call. Row 199 matches a range's `-1` endpoint without checking its start. Row 162 matches a clause shape through a `var_name(a) == var_name(b)` guard whose helper returns `nil` for every non-variable, so the guard is vacuously true on any two non-variables. This deserves a line in the rule-authoring prompt: *a rule that matches a leaf token must name the construct that encloses it, and a guard of the form `f(a) == f(b)` is invalid if `f` can return a sentinel.*

**3. Rule premises are being asserted by the classifier and never checked, and each false premise costs a full 80-turn implementer run.** Row 221's stated motivation — a `--warnings-as-errors` failure from `incompatible types given to Kernel.*/2: float(), dynamic()` — does not exist; I compiled the exact shape with `elixirc --warnings-as-errors` and it is clean, because `dynamic()` is compatible with `float()`. Row 150 attributes an always-invalid ETS option to "OTP 27+ (stdlib 7.3)". Row 162 asserts a clause deletion is safe when it is not. Row 199 claims the deprecated slice yields `""` when it still yields the suffix. A cheap pre-dispatch gate — compile and run the classifier's BEFORE, and require the claimed diagnostic or crash to actually appear — would have killed 150, 162 and 221 for the price of one compile, roughly $100 of implementer budget across just my nine rows. This is a new harness item, not covered by LD1–LD4.

**4. Systematic harness/test-framework defect (new, not in docs/16): `test/support/behaviour_equivalence.ex:312 compile_module!/2` cannot compile any module that uses its own struct.** It renames only the `defmodule` header (`String.replace(…, global: false)`), leaving every `%Money{}` in the body pointing at the vanished original name. Reproduced: `error: Money.__struct__/1 is undefined, cannot expand struct Money … cannot compile module Eqv_Before_1`. This alone consumed row 225's entire 81-turn budget and pushed it to `mark_equivalence_unconstructible`. It is a one-line class of fix (word-boundary global rename, or inject an alias) and it directly inflates the `mark_equivalence_*` population that Phase 8.2/H4 is being built to insure against — H4's scope estimate is measuring this bug, not a real limit.

**5. Environmental kills are being booked as substantive failures.** Row 169 stopped at step 41, 23 of 80 turns used, on a provider-side "The request was rejected because it was considered high risk" (triggered, most likely, by a `mix run -e` heredoc containing deliberately malformed Elixir). The harness recorded `agent done — subtype=success` and the Router filed `gave_up: {:cc_tests_red, …}` quoting the scaffold's own untouched placeholder assertion, `left: "foo(bar)" / right: "baz(qux)"`. H9 currently scopes environmental triage to timeouts and 429s; it must also key on the refusal string and on the signature "turns used far below cap **and** scaffold placeholders still present", or rows like this get dropped on the "second failure" policy having never been genuinely attempted.

**6. Appendix A's verdicts held for 6 of 9 rows; the three misses all point the same way — it under-read the rows where the log contradicts the summary.** It calls 144 "likely drop" when the target is a verified crash-repair with no credence coverage and the only failure was the agent's own `Macro.postwalk` accumulator bug. The preserved corpus.md for 199 heads its section "likely an OVER-FIRE → DROP" when half the hits are real deprecation sites — including one in credo, this repo's own dependency. And 169/225's "one retry, drop on second failure" would discard both rules, since neither can succeed until the misclassification (169) and the `compile_module!` defect (225) are fixed. Net disposition for my nine: 4 DROP (150, 162, 221, 145/178 as LD3 pairs — counting 145 and 178 that is 5), 3 RE-QUEUE (144, 169, 225), 1 ACCEPT with a named one-predicate narrowing (199), plus two credence/harness defects worth filing on their own (`behaviour_equivalence.ex:312`; the missing premise-verification gate).

### behaviour_diverged (all 13)

SCOPE. All 13 rows are classify-time kills in Cev.Evolve.Router (lib/cev/evolve/router.ex:137). Nothing was built, so the cluster holds only .log files — no .patch, no .corpus.md, nothing to apply. Every log was read end to end and every verdict reproduced offline (script at /tmp/claude-1000/-home-kamil-projects-credence/de0c5562-40d5-4e36-9bd7-8c3b9c27f852/scratchpad/p5-diverged/repro.exs, a verbatim port of Cev.Equiv.extract/1 + credence.equiv's classify/5 over the real battery): all 13 reproduce byte-for-byte, including row 105's WithClauseError, row 185's input=[1] and row 33's 7-frame stacktrace.

DOCS/16'S CLAIM IS ~10/13 TRUE, AND ITS DIAGNOSIS IS WRONG IN A WAY THAT MATTERS.
Appendix A says all 13 are "before = raise UndefinedFunctionError by construction, so any working after looks divergent — the probe is asymmetric and vacuous". Three corrections:
  (a) Row 105 is a TRUE POSITIVE in the opposite direction. before = WithClauseError; the AFTER raises UndefinedFunctionError because the proposed fix rewrites `File.stream!/1` (exists) to `File.stream/1` (does not exist — verified `function_exported?(File, :stream, 1) == false` on Elixir 1.20.2). It is also phase-mismatched: the row fails at runtime with no compiler diagnostic at all, so a Semantic rule could never fire on it. Re-queueing it as prescribed would push a compile-breaking rule back into the pipeline.
  (b) Row 185 does not fit "by construction" either: its before raises on 41 of 44 inputs, not 44, because `Enum.all?([], &DateTime.valid?/1)` short-circuits. A different clause of the predicate fails.
  (c) The probe is NOT missing a vacuous-repair class. credence.equiv already has one — `REPAIR` (lib/mix/tasks/credence.equiv.ex:17-20, 115-133), defined as "before raised on EVERY input AND after succeeded on >= 1" — and Cev.Equiv routes it straight to build (lib/cev/equiv.ex:31, router.ex:143). Rules of exactly this class DID ship through it (committed/164's log: "marked as repair (mark_equivalence_repair) since the before code always raises FunctionClauseError"). So the gate design is right; two implementation defects deny it.

THE TWO REAL HARNESS DEFECTS (both in credence, not the harness repo).
  H-A (10 of 13 rows: 1, 7, 12, 18, 31, 106, 107, 162, 164, 205). The default equivalence battery is type-blind. @all_dims (credence.equiv.ex:66) = [term_lists, signed_integers, stability_lists, unicode_strings, single_codepoint_strings, multi_codepoint_strings], and all 44 resulting values are lists or binaries — `signed_integers` returns lists of integers, not integers. There is no map, struct, MapSet, %Task{}, tuple, keyword list or scalar number anywhere. Consequently any repair whose fixed code needs one of those raises on 100% of inputs, `repair?/1`'s "after succeeded on >= 1" clause can never be satisfied, and the row falls through to DIVERGES. Measured: 10 rows sit at before_raised 44/44, after_ok 0/44. Adding %{}, MapSet.new/1, bare 0/1/5, ~D/~N/~U and a real %Task{} flips all 10 to REPAIR(strict). This is Phase 6.2's C2.1-rest item (maps, keyword_lists, tuples, mixed_numeric) — it needs structs and MapSet added to the list, and it is the single highest-leverage fix in this cluster.
  H-B (row 185). `repair?/1` (credence.equiv.ex:131-134) demands the before raise on EVERY input, so one input on which the hallucinated call is short-circuited away kills the verdict. Tolerating already-agreeing pairs — `match?({:raise,_}, ob) or ob === oa` — flips 185 to REPAIR on the unchanged battery.
  H-C (row 33, distinct class). classify/5 compares outcomes with strict `===`, so any term containing a stacktrace is uncomparable. Needs normalization in behaviour_equivalence.ex's run_outcome/eval_outcome.

WHY LD2 AS DRAFTED IS THE WRONG FIX. docs/16 §8.1 proposes treating `before = {:raise, UndefinedFunctionError}` as vacuously passable. That accepts on the strength of the BEFORE alone, so it cannot distinguish "the after works" from "the after is also broken" — it would greenlight any proposal whose repair is itself hallucinated. Fixing the battery is self-guarding by comparison: it still demands the after produce a real value, so it unblocks the 10 productive rows while leaving row 105 DIVERGES (verified: after_ok = 0/56 even with the extended battery). Recommend H-A + H-B + H-C in place of LD2, with row 105 wired in as the mandatory positive control (a gate nobody has seen red is unverified — Appendix B).

A THIRD DEFECT THE CLUSTER EXPOSES BY ACCIDENT. Cev.Equiv.extract/1 returns :error on any spec it cannot parse, and check/2 maps that to :skipped — i.e. the probe is silently bypassed. committed/12 proposed the SAME rule as behaviour_diverged/12 and was built only because its ===AFTER=== block ends with `}` instead of `end`. A classifier typo is currently a way past the equivalence gate, while a well-formed spec is killed. Worth a distinct Phase 8 item: :skipped should be logged (today only the :diverges branch logs, router.ex:139), and an unparseable spec should be an error, not a pass.

VACUOUS-PASS MIRROR (latent, no row here). classify/5 returns :equivalent whenever before and after agree on every input — including when both raise the identical exception class on every input. A proposal that swapped one hallucinated call for another hallucinated call would therefore PASS today. The battery fix narrows this too; worth a guard regardless.

NET DISPOSITION. 8 RE-QUEUE (1, 7, 18, 106, 107, 162, 164, 205 — all blocked on H-A; merge 1+18, they are the same rule), 3 FIX-HARNESS (31 carrying H-A as its minimal repro, 185 = H-B, 33 = H-C), 2 DROP (12 superseded by the shipped lib/semantic/fix_hallucinated_naive_datetime_accessor.ex; 105 a correct kill). Every re-queued target is confirmed still uncovered: I grepped credence's lib/ for Map.empty?, MapSet.empty?, Float.coerce, DateTime accessors, Date.to_tuple, Task.stop, Task.pid, DateTime.valid?, make_tuple, System.stacktrace and File.stream — only the NaiveDateTime accessors have shipped, and none of the others appear in undefined_function.ex's replacement tables. Four of the eight (Float.coerce, Date.to_tuple, Task.stop, and arguably :erlang.make_tuple) are one-line entries in that table rather than new rules; Task.pid is a copy of the shipped fix_task_ref_field_access.ex. The stakes stated in the assignment hold up: this is the harness's most productive rule class, and a single type-blind input battery is what auto-kills it.

### classifier_errors (all 52)

## The counts check out; the diagnosis in docs/16 does not

Verified exactly: 44 `rule_name_not_in_closed_set`, 6 `decision_not_offered` (rows 6, 27, 54, 59, 210, 224), 1 `bad_decision` (28), 1 `does_not_parse` (211). Appendix A's arithmetic is right.

Its causal claim — "closed-set construction or name normalisation is broken" — is half right and misses the dominant mechanism. There are **five** distinct defects, and the biggest one is neither.

## LD1-a (DOMINANT): the row log truncates and the `APPLIED_RULES` line falls off the end

`lib/cev/validator.ex:347` logs the *entire* credence-fix stdout as ONE message:

    Logger.debug("[run_credence_fix] exit=#{code} output:\n#{output}")

`config/config.exs:231` sets `config :logger, level: :debug` and **never sets `:truncate`**, so Elixir's default 8096-byte limit applies. Measured on `classifier_errors/90.log`: the message is cut at exactly 8097 bytes with `(truncated)`. Credence's `RuleHelpers.log_diff/3` prints a full before/after line dump for every rule that changes the source, and `APPLIED_RULES:` is printed **last** by the script (`lib/cev/workspace.ex:49`) — so it is the first thing lost.

Measured scale:
- **classifier_errors: 48 of 154 fix invocations (31%) lost their `APPLIED_RULES` line.**
- **Whole run, all clusters: 336 of 1416 (23.7%).**
- Correlation is perfect: every missing line has `(truncated)` in that block. The single exception is row 54, where the script died at `exit=1`.

Worked example (row 90): attempt 3 logs `NoBareNamesInSpec: matched diagnostic` → `source CHANGED`, so the rule *was* in `applied_rules` — but the diff blew the budget and the line never reached disk. `Cev.AppliedRules.parse/1` saw 2 of 3 attempts, the closed set lost the rule, and the classifier — which reads the distilled log and *can* see `NoBareNamesInSpec: matched diagnostic` — named it correctly and was rejected. Same story in rows 6, 7, 10, 27, 38, 65, 67, 69, 87, 88, 99, 112, 119, 122, 134, 150, 156, 175, 179, 181, 192, 210, 213, 224.

**Status: already fixed, today, and not by Phase 5.** Commit `60ce2c4` ("H12: make the APPLIED_RULES hand-off a real contract, not a log level") added `Cev.RowLog.write_sidecar("applied_rules", output)` and `Cev.AppliedRules.for_row/1`, and `router.ex:49` now reads the sidecar. Residual holes worth closing:
- `Cev.Classify.run/3` (classify.ex:41) still defaults `:closed_set` to `log |> AppliedRules.parse()` — dead in production only because the Router always passes it explicitly.
- `Cev.AppliedRules.@line` (`~r/APPLIED_RULES:\s*\[(?<body>.*)\]/`) requires a closing `]`, so a line truncated *mid-list* is discarded whole rather than partially parsed. 3 lines run-wide; row 145 is one.
- The **distilled log** the classifier reasons over is still truncated by the same 8096-byte limit. H12 rescued the closed set, not the evidence.

## LD1-b: Pattern (and Syntax) no-op fixes are erased from the trace

`credence/lib/pattern.ex:156-158`:

    fixed == source ->
      Logger.debug("[credence_fix] #{name}: fix returned IDENTICAL source (no change)")
      {source, applied}          # <-- NOT recorded

`lib/syntax.ex:74-75` does the same. `lib/semantic.ex:152` does **not** (it records `{rule, 1}` unconditionally). So "rule detected the issue and produced nothing" — the single most valuable BUGFIX class — is structurally unrepresentable for two of three phases. Rows 1, 23, 125, 138, 139, 141, 203, 227 (and 95) are exactly this: the log says `X: check found N issue(s), running fix...` and the `APPLIED_RULES` line on the very next line omits X. Row 139 is the cleanest specimen — three attempts, `NonGroupedClauses: check found 1 issue(s)` each time, `APPLIED_RULES: [{Credence.Semantic.UnusedVariable, 1}]` each time.

This is docs/16 C5 ("surface the silent patch-drop path"); it needs a `{rule, :no_op}` entry, and the harness needs to accept `:no_op` entries into the closed set. Until then those eight rows will re-fail identically on re-queue.

## LD1-c: a crashing Pattern rule takes the whole trace with it

Row 54: `Credence.Pattern.NoMapKeysOrValuesForIteration.rebuild_call/2` raises `FunctionClauseError` on `&:queue.is_empty/1` — reproduced live on credence HEAD. The exception escapes `Pattern.fix_with_trace/2` (no per-rule isolation — credence C6), kills the fix script (`exit=1`), and **zero** `APPLIED_RULES` lines are emitted for all three attempts. So the rule that broke the run is the one rule that can never be named. The harness should treat `exit != 0` from the fix script as a distinct, escalatable signal rather than an empty closed set.

## LD1-d: no name normalisation — the prompt and the gate speak different languages

`Cev.Classify.Prompt.build/1` renders two rule namespaces to the model:
- `## Existing rule index` — **all** clone rules as `<phase>/<name> — <intent>` (from `Cev.RuleIndex.build/2`),
- `## Rules that already fired` — module names, `Credence.Semantic.Foo`.

`Cev.Classify.Parser.rule_name/1` then does `:"Elixir.#{raw}"` with **no normalisation at all**. Nine rows emitted the index's spelling and were annihilated: `:"Elixir.pattern/non_grouped_clauses"` (95), `:"Elixir.no_after_or_rescue_in_case"` (49), plus `lib/semantic/x.ex` / `semantic/x` / `syntax/x` forms in 6, 27, 28, 54, 59, 210, 224. Row 95 also shows the softer variant: `Credence.Semantic.NonGroupedClauses` for a rule that lives in `Credence.Pattern` — right rule, wrong phase segment. Fix: map `<phase>/<snake>` → `Credence.<Phase>.<CamelCase>`, strip `lib/` and `.ex`, and resolve by basename when the phase segment is wrong.

## LD1-e: the prompt asks for a decision the gate cannot accept

NO_ACTION class 2 in `prompt.ex:110-115` says, of the **full rule index**:

> If that existing rule MIS-fired on THIS row, that is a BUGFIX_RULE, not a new rule.

But `classify.ex:115` requires `name ∈ closed`, where `closed` is "rules that fired *and changed the source*". The **under-fire** class — "this rule exists, it should have matched this diagnostic, it did not" — is by construction absent from `applied_rules`, so the prompt actively solicits a decision the validator must reject. That is the honest reading of Appendix A's "rules that exist in-repo": rows 20, 22, 67, 77, 115, 122, 129, 134, 136, 145, 150, 156, 164, 171, 176, 183, 192, 196, 228 named real rules that genuinely did not fire. The gate was right; the prompt was wrong. Either add a `RULE_UNDER_FIRED` decision keyed to the rule index, or stop telling the model to report under-fires as BUGFIX.

## A sixth defect, credence-side, that feeds two of the above

`credence/lib/rule_helpers.ex:938` `log_diff/3` pairs lines **positionally**, so any insertion or reorder renders as a whole-file rewrite. This (a) fabricated row 181's "catastrophic replacement" bug report out of a correct module reorder, and (b) is the thing that blows the 8096-byte Logger budget in the first place. One fix — a real, bounded diff — kills a false-positive source and shrinks the truncation surface.

## What the rows are actually worth

Of the 44 closed-set rejections, **20 name rules deleted in Phase 4.6c** and already dispositioned in docs/18 — those reports have no target and are DROPs. **8 concern live rules with reproduced defects** (FIX-CREDENCE: 54, 65, 90, 115, 145, 164, 183, 192, 196). **9 are live-rule no-op reports I could not reproduce** and are worth one re-queue behind the lib/pattern.ex:158 fix. **4 reports are simply wrong** (112 — `nil == :nil` is `true`; 181 — diff artefact; 122 and 213 — already repaired in Phase 4; 27 — over-fire already guarded).

Net: the cluster is worth **one harness commit (normalisation + prompt/gate reconciliation + the `@line` and `exit != 0` edges), one credence commit (`lib/pattern.ex:158` + `log_diff`), and eight rule bugfixes** — of which `FixLocalFunctionInGuard` accounts for four rows in one file, and `NoBareNamesInSpec` for two.

## One correction to the Phase 5 / 6.5 worklist

docs/16 §6.5 lists "NoRemoteFunctionInGuard `:do =>`" as a Phase 6 bugfix. The bug is real — I verified `if(x, :do => :ok, :else => y)` is a hard `syntax error before: '=>'` and the harness's own compile gate reverted it — but the module is **not in credence**, and docs/18 already dispositions it `rebuild-later-from-catalogue` with instructions to delete the file and keep only `match?/1` + `to_issue/1`. The salvage belongs in FAILURE_MODE_CATALOGUE #11 (as a third corruption path, alongside the two body-hoist corruptions and the guard-deletion hole already recorded), not on a bugfix worklist. The row-90 item, by contrast, is correctly filed and I have strengthened it with an exact reproduction.

### switch_proposals

switch_proposals is a one-row cluster (2.json + 2.log, 223 KB, no .patch, no .corpus.md) and it is the only switch proposal of the entire 1,280-row / 5-pass run. That scarcity is itself the cluster's main finding, and it corroborates docs/16 §4.4's conclusion that `proposed_assumptions.md` staying empty is a result rather than an omission: across the whole run the meta-classifier reached for a safety switch exactly once, and that once was a misfire.

The systematic harness defect this cluster exposes is bigger than the row. `Credence.RuleHelpers.compile_and_capture/1` (credence/lib/rule_helpers.ex:160-186) compiles with `Code.compile_string/2` and no `ignore_module_conflict`, so when the target module is already loaded the diagnostic stream gains a `severity: :warning, position: 1, "redefining module X (current version loaded from …/_build/test/lib/workspace/ebin/Elixir.X.beam)"` entry that is a property of the host VM, not of the source under analysis. The harness guarantees that state: `Cev.Validator.run_credence_fix/1` runs `mix run --no-compile run_credence_fix.exs` inside the persistent, already-compiled `var/run/workspace`, and the `credence check` step is invoked the same way. I reproduced the phantom warning in isolation (preload module → `compile_and_capture/1` returns it; cold VM returns `{:ok, []}`).

Three distinct kinds of damage follow, all visible in the logs: (a) the phantom warning is offered to every semantic rule's `match?/1`, so the harness's semantic phase is not representative of real credence usage and any evolved rule may key on a diagnostic that only exists in the harness — one already did; (b) it produces false ISSUES and flips validator steps (committed/37.log:1274 shows `credence check exit=1` on the bogus issue alone); (c) it fabricates evidence for the meta-classifier, which is exactly how this switch proposal came to exist and how the false claim 'the incumbent rule's fix is confirmed broken' propagated into docs/16 §4.4 and Appendix A. `redefining module` appears in at least ten logs across escalated/, committed/ and classifier_errors/, so the contamination is not confined to switch_proposals — rows in other clusters should be re-read with the possibility that a matched 'diagnostic' was this artefact.

A second, smaller cluster-level lesson: the row's proposal was written against a rule version that no longer existed by the time the plan was drafted. `@match_msg` changed from "redefining module" to "has multiple clauses and also declares default values" on 2026-07-13, six days after this run (2026-07-07). Any triage that reads a log's rule behaviour must pin the rule to the run's timestamp (`git log --format=%ad` on the rule file) before concluding the rule is buggy — otherwise it will diagnose the wrong implementation, which is what happened here.

---

## Per-row decisions

### escalated 2–78

#### row 2 — **FIX-HARNESS**  ·  `Gate / proposed Credence.Semantic.NoErbSendAfterInfinity`

The candidate passed the mutation gate (`mix test <2 changed files>` exit=2, "mutation OK"), then `mix test --exclude corpus` returned exit=1 after **4.7 s** and the Gate logged `:full_suite_red`. The suite never ran: the run died in `Kernel.ParallelCompiler.wait_for_messages/8` with `** (ErlangError) Erlang error: :terminated` from `:io.put_chars(:standard_error, ["    warning: default values for the optional arguments..."])` — the stderr device was gone while printing a compile diagnostic. The implementer's own agent had run the identical command 4 minutes earlier (22:32:54) and reported "All 7309 tests pass, 0 failures". So the Gate maps *any* non-zero exit of `mix test` to "suite red" and discards, with two free discriminators unused: no `Finished in … tests, … failures` line was emitted, and 4.7 s vs the ~2 min baseline.

*Follow-up:* RE-QUEUE. The trigger (6 warning-carrying test files forcing the stderr write) was removed in Phase 4.2, so the row is safe to re-run as-is; the Gate fix is H9/8.4. Overlap note: switch_proposals/2.json (`fix_process_send_after_infinity`) and escalated/20 are two more views of the same catalogue item — docs/18's `no_process_send_after_infinity` entry says the switch decision "must be folded into this same deletion rather than left dangling". Let the switch_proposals agent own the proposal.

*Appendix A:* Partly. It reaches the same action (re-queue) but the mechanism is wrong: it blames "pre-existing warnings in 4 sister test files + a `NoKeywordIfBareInTuple.fix/1` crash". `NoKeywordIfBareInTuple` appears nowhere in 2.log (grep: zero hits) — that belongs to rows 100/119. And the warnings are the trigger, not the cause: the cause is the stderr device returning `:terminated`, which any stderr write would hit. Appendix A also does not name the Gate defect at all.

#### row 6 — **RE-QUEUE**  ·  `proposed Credence.Semantic.FixRecursiveVariableInPattern`

Not a scaffold-hardness failure. The implementer agent ran 25 steps that are **all Read/Glob/Grep — zero Edit and zero Write** (verified by grepping every `step N: Edit|Write` after the agent start: 0 hits), stalled for 3.5 min after step 25, then terminated `subtype=success turns=17` (of a max of 80). The Router then reported `gave_up: {:cc_tests_red, ... left: "foo(bar)" right: "baz(qux)"}` — those are the untouched scaffold placeholders, i.e. the stub tests were never even opened for editing. The proposed failure mode is real and uncovered: `def handle_call(:get_state, _from, state = %{state: state})` → "recursive variable definition in patterns"; nothing in `lib/semantic/` or `lib/pattern/` handles it (`fix_cyclic_struct_reference.ex` is a different target) and it is not in docs/18.

*Follow-up:* FIX-HARNESS — the Router should treat an implementer session that wrote no files as a null run (retry / distinct outcome), not as `:cc_tests_red`. Also LD1 evidence in this same log: `[Classify] re-ask after invalid spec: {:rule_name_not_in_closed_set, Credence.Syntax.NoKeywordIfInTuple}` — a one-word near-miss for the real `Credence.Syntax.NoKeywordIfBareInTuple`.

*Appendix A:* Agrees on the action ("one retry each next run; drop on second failure"). Disagrees on cause: it says "placeholders never made green; 80-turn cap". The cap was never approached (17/80) and the agent made no edit at all — that is a different, fixable failure than "hard task".

#### row 20 — **DROP**  ·  `Credence.Semantic.NoProcessSendAfterInfinity`

The classifier's BUGFIX claim ("matched the diagnostic but returned IDENTICAL source") was never tested: the agent ran the focused tests + full suite, found them green, staged nothing (`staged entries: []`), and concluded "No edits were needed". Its own summary gives it away — it describes `match?/1` as keying on the *"redefining module" diagnostic* and `fix/2` as "replacing the def body with a comment + `:ok`", which is neither a real Elixir diagnostic nor a sane repair. Phase 4 reached the same conclusion independently and harder: docs/18-per-rule-verdicts.json marks the rule `rebuild-later-from-catalogue`, "implementation dead: no diagnostic exists, fix corrupts working code", and it plus both siblings (`no_process_send_after_literal_infinity`, `no_process_send_after_with_variable_infinity`) were deleted in credence_evolution b83d623. Nothing to fix — the file is gone (`find` in both repos: no `*send_after*` rule remains except `no_process_send_after_infinity` referenced only in a stage-1 review log).

*Follow-up:* Delete the artefacts. The failure mode itself is already preserved as catalogue item #5 (report-only → corrected to one fixing pattern/AST rule, expression-scoped, switch-gated) and is the same item rows 2 and switch_proposals/2 point at. No re-queue: the deliverable is a new rule, not this row.

*Appendix A:* Yes — it files this under `:no_lib_change` with "no per-row action; feeds LD3/LD4". I add the docs/18 cross-check that closes it permanently.

#### row 40 — **DROP**  ·  `Credence.Syntax.NoPythonMultiReturn`

The over-fire was REAL and is visible in this very log — at 15:43:19 the solve-phase `credence_fix` trace shows `NoPythonMultiReturn: source CHANGED` rewriting `{QueueManager, max_queue, name},` → `{{QueueManager, max_queue, name},}` and `__MODULE__,` → `{__MODULE__,}`, after which "source still does not parse (line 55)". The agent nevertheless concluded "the rule already correctly handles child spec tuples … the fix was simply adding regression tests", staged only the two test files, and the Gate rejected `:no_lib_change`. I compiled credence_evolution HEAD's copy of the rule side-by-side with the accepted credence version and fed both lines in: **EVOHEAD fires on both (`analyze` returns an Issue, `fix` changes the line); the accepted credence version fires on neither.** So the bug survived all ten `bugfix(over_fire)` commits and was only killed by Phase 4's acceptance rewrite (17bec10), whose `wrapped_line/1` rejects a trailing depth-0 comma and requires the line to fail-parse-then-parse-wrapped. Row dated 2026-07-13 13:56 UTC (rows.jsonl ts 1783950968; log wall-clock is UTC+2, which matches the 15:56:08 REJECT exactly).

*Follow-up:* Delete the artefacts, but feed two things forward: (a) LD3 — the agent's regression tests were the *right* output and `:no_lib_change` threw them away; (b) FIX-HARNESS, see cluster findings — the classifier's minimal BEFORE is never checked against the rule it accuses, so the agent verified a repro that does not reproduce. Do NOT record this as "rule was already correct".

*Appendix A:* No. Appendix A files it under "`:no_lib_change` (rule already correct)". The rule was not correct at the time — the over-fire is printed in the log — and it stayed broken through the end of the run. It is correct now, for a reason Appendix A does not mention (the Phase 4 acceptance rewrite, not any evolution bugfix).

#### row 48 — **DROP**  ·  `proposed Credence.Pattern.NoStacktraceInTerm`

810 corpus over-fires, and the rule's premise is a misread stack trace. The originating crash (48.log:2361) is `** (FunctionClauseError) no function clause matching in :gen.reply/2` — because the solution called `GenServer.reply(caller, …)` with `caller = self()`, a bare PID, after doing `GenServer.cast` + a manual `receive`; `:gen.reply/2` needs a `{pid, tag}` from-tuple. The `stacktrace: __STACKTRACE__` in the payload is incidental — it only appeared in the printed arguments. Stacktraces are ordinary serializable terms. The rule flags every bare `__STACKTRACE__` not already inside `Exception.format_stacktrace/1` and wraps it, which converts a **list into a String** — the harness's own prompt bans exactly this ("NEVER generate a rule whose fix changes the TYPE of the value the code produces"). I categorised a random 40-hit sample of 48.corpus.md against the real corpus: 16 `reraise`, 10 `Exception.format(kind, err, __STACKTRACE__)`, 3 `:erlang.raise/3`, 11 "other" (all list-typed contracts such as `Exception.blame/3` and handler functions). All three of the first groups raise `ArgumentError`/`FunctionClauseError` on a formatted string. Effectively 810/810 false positives with a program-breaking rewrite. The log's own tail shows `:erlang.raise(kind, error, __STACKTRACE__)` in db_connection being rewritten.

*Follow-up:* Delete 48.patch and 48.corpus.md; add `no_stacktrace_in_term` to the classifier's rejected-over-fire list for H8. There is no failure mode worth keeping — the underlying bug was `GenServer.reply/2` given a PID, which is a different (and genuinely useful) rule idea.

*Appendix A:* Yes on the action. It says only "fires on ubiquitous idiomatic code"; I add the decisive part — the rule was born from a misdiagnosed stack trace, and its rewrite is a banned list→String type change, so it is unsalvageable rather than merely too broad.

#### row 50 — **DROP**  ·  `Credence.Syntax.NoPythonMultiReturn`

Same shape as row 40. The over-fire is in the log: at 01:25:46 `NoPythonMultiReturn: source CHANGED` rewrote `                  | prev_delay: capped_delay,` → `{| prev_delay: capped_delay,}` inside a `%{exec_state | …}` struct-update, on a file whose real parse error was elsewhere (line 68, `Map.get(state, :executions, %)`). The agent then declared "the cross-line depth tracking places all lines inside `%{}` at depth ≥ 1, so … no rule source changes were needed", staged two test files, Gate rejected `:no_lib_change`. Dating: rows.jsonl ts 1783553480 = 2026-07-08 23:31:20 UTC = the log's 01:31:20 local (UTC+2). The `has_struct_pipe_at_depth_zero?` guard that fixes this shape was added by credence_evolution a7c6985 on 2026-07-09 — **after** this attempt. I verified both the evolution-HEAD and the accepted credence versions now return `analyze == []` / no change on that exact line.

*Follow-up:* Delete the artefacts. Same two feed-forwards as row 40 (LD3 test-only-diff policy; the unvalidated-minimal-repro harness fix). Do not record as "rule already correct".

*Appendix A:* No — same disagreement as row 40. "Rule already correct" is false for the moment the row ran; the guard landed a day later.

#### row 55 — **DROP**  ·  `proposed Credence.Semantic.NoTrapExitWithoutExitHandler`

Dead by construction, independently of how the session ended. The agent's rule declared `@match_msg "trap_exit set in init without EXIT handler in handle_info"` and `match?(%{severity: :warning, message: msg}) when is_binary(msg), do: msg == @match_msg` — a diagnostic string the Elixir compiler never emits. `Process.flag(:trap_exit, true)` with no `{:EXIT, _, _}` `handle_info` clause produces **zero compile diagnostics**; it is a pure runtime `FunctionClauseError`. A semantic-phase rule is only ever invoked from a compiler diagnostic, so this rule could never fire in production no matter how green its tests got. Separately, the session did not fail on merit: at 05:07:43 (step 75, mid-`Edit`, having just rewritten `build_exit_handler/0`) the log records `API Error: Request rejected (429) · quota exhausted`, and the Router still reported `gave_up: {:cc_tests_red, …}`. The Router also noted at 04:54:51 "an existing rule may overlap this idiom (non-blocking)" — I could not corroborate that: no `trap_exit` rule exists in credence, credence_evolution, or docs/18.

*Follow-up:* Delete the artefacts, but record the failure mode first (per the standing rule that a rule's value is its failure mode): *a GenServer that sets `Process.flag(:trap_exit, true)` and has no `{:EXIT, pid, reason}` `handle_info` clause crashes with `FunctionClauseError` on the first linked-process exit; zero compile diagnostics; real, recurring, and uncaught by all live rules.* Its home is the **pattern** phase (AST, no compiler oracle needed), not semantic. Also count the 429 toward Phase 9.4 capacity, and toward H9: a quota kill must not be reported as a merit-based give-up.

*Appendix A:* Outcome yes ("144/55 likely drop"), reason no. Appendix A calls it a "`no_trap_exit_without_exit_handler` overlap" problem. The overlap note in the log was non-blocking and I found no rule it could overlap. The real disqualifier is the invented diagnostic string / wrong phase, and Appendix A misses that the give-up was a 429 quota kill mid-edit rather than an implementation failure.

#### row 59 — **DROP**  ·  `Credence.Syntax.NoPythonMultiReturn`

The most clear-cut of the three. At 21:05:02 the solve-phase trace shows `NoPythonMultiReturn` mangling **six** struct-update lines at once — `| paused: true,` → `{| paused: true,}`, `| maintenance_ends_at: nil,` → `{| maintenance_ends_at: nil,}`, etc. — turning a file whose only parse error was at line 226 into one that fails at line 121, followed by `[run_credence_fix] fix broke compilation — reverting`. Forty minutes later the agent reported "The rule correctly doesn't fire on map struct updates … because the commas are inside `%{}` at depth 1", staged the two test files, `:no_lib_change`. rows.jsonl ts 1783539997 = 2026-07-08 19:46:37 UTC = the log's 21:46:37 local — again before a7c6985 (07-09) added the struct-pipe guard. Both today's versions are clean on that line (probed: `analyze == []`, `fix` identity).

*Follow-up:* Delete the artefacts. This row is the sharpest evidence for the harness fix in the cluster findings: the classifier's reduced BEFORE (`%{service | status: if service.active, do: :up, else: :down, paused: false}`) does not reproduce the accusation at all — I ran it through the current pipeline and `NoPythonMultiReturn` returns `[]` while `NoKeywordIfBareInTuple` correctly produces the classifier's own proposed AFTER. The agent verified the repro, not the bug.

*Appendix A:* No — same disagreement as 40/50, and here "rule already correct" is contradicted by six mangled lines and a revert inside the row's own log.

#### row 73 — **DROP**  ·  `proposed Credence.Pattern.NoDiscardedEarlyReturnGuard`

1064 corpus over-fires, all traceable to one clause in the patch: `defp terminal_style_expr?({:raise, _, _}), do: true` (plus `:throw`/`:exit`). I categorised a random 50-hit sample of 73.corpus.md against the real corpus: **49 `raise`, 1 `throw`, 0 error-tuples** — i.e. every hit is the canonical Elixir precondition guard (`unless key in @valid_keys do raise ArgumentError, … end` in sentry, `if Nx.rank(tensor) != 1 do raise … end` in scholar, and so on). A raising body is a non-local exit; nothing is "discarded" and the premise simply does not apply. The rewrite would invert 1064 correct guards and nest the whole remainder of each function inside an `else`. The `find_discarded_guard/1` criterion is only `idx < length(stmts) - 1`, so it flags essentially every validate-then-continue function in Elixir.

*Follow-up:* RE-QUEUE, narrowed and switch-gated. The failure mode is genuine and recurring — the row's own rationale says "All 3 solve attempts hit this exact bug": `unless partial or items == [] do {:error, items} end` followed by `Enum.sum(items)`, where the value is discarded and the early return never fires. Deleting the `raise`/`throw`/`exit` arms of `terminal_style_expr?/1` takes the sample from 50/50 hits to 0/50. But note the narrowed rule is still a **behaviour change** on compiling code (before: always returns the tail; after: returns `{:error, …}` when the condition fails), so under §3.10 it cannot ship as a plain pattern rule — it needs `assumptions/0` and a switch, exactly like `fix_process_send_after_infinity`. Record the failure mode in the catalogue before deleting 73.patch/73.corpus.md; add the name to H8's rejected-over-fire list in its *current* form only.

*Appendix A:* Yes on "drop", and it is right that it fires on ubiquitous idiomatic code. It does not identify the single responsible clause, does not record the failure mode, and does not note that the salvageable core needs a switch rather than a narrowing.

#### row 78 — **FIX-CREDENCE**  ·  `Credence.Semantic.NoPlugUploadSizeField → lib/rule_helpers.ex + lib/semantic.ex`

The agent's conclusion ("the existing rule already implements the fix correctly … no changes are needed", `staged entries: []`) is a symptom, not the finding: the rule's tests are green because they hand it a hand-built diagnostic map, while in production the diagnostic never arrives. I reproduced the cause live at credence HEAD, read-only:

  Credence.RuleHelpers.compile_and_capture(src) #=> {:ok, [%{severity: :error, message: "unknown key :size for struct ProbeStruct"}]}
  Credence.Semantic.analyze(src, [])            #=> []
  Credence.RuleHelpers.compiles?(src)           #=> true

`Code.compile_string/2` still returns modules for Elixir 1.19 **type-checker** errors, so `compile_and_capture/1` (lib/rule_helpers.ex:173-185) tags them `{:ok, diagnostics}`; `Credence.Semantic.analyze/2` (lib/semantic.ex:22-25) and `do_fix_traced/4` (lib/semantic.ex:88-92) then filter that branch to `severity == :warning` and drop every `:error`. The entire "== Type checking failed with errors ==" class is silently dead, and `compiles?/1` reports `true` for source `elixirc` rejects — so the Pattern phase's compile gate is wrong too. Seven live semantic rules key on this text: no_stream_data_tuple_with_list, no_message_access_on_rescue_variable, no_naive_datetime_new_with_tuple, fix_fn_arity_in_keyword_value, no_hallucinated_datetime_zone, fix_task_id_field_access, fix_jason_decode_error_message_field (`@match_msg "unknown key :message for struct Jason.DecodeError"`).

*Follow-up:* Fix: treat an `{:ok, diags}` result containing any `severity: :error` as `{:error, diags}` in `compile_and_capture/1`, then re-verify all seven rules above and add a positive control. Then DROP row 78's artefacts — `no_plug_upload_size_field` itself is `delete-implementation-dead` in docs/18 and the file is gone from both repos. docs/18's `no_plug_upload_size_field` entry raised this same defect and asked for it to be filed against the live repo; it was not among the nine Phase 4 repairs, and I confirm it is still live at HEAD (26d14e6).

*Appendix A:* No. Appendix A files 78 under "`:no_lib_change` (rule already correct)" with no per-row action, which takes the agent's conclusion at face value. docs/18 has the right analysis; Appendix A does not carry it, and the resulting defect is live and shipped.

### escalated 82–137

#### row 82 — **DROP**  ·  `Credence.Semantic.FixPlugDependencyModuleOrder (classifier called it NoPlugBeforeDependencyDefinition)`

The classifier's premise — "the rule matched this diagnostic but returned identical source" — was already false when the row ran. The alias-resolution repair it asks for had been committed 11 h earlier by an EARLIER pass of the SAME row (e7d383a, `cred-gen: bugfix(over_fire): lib/semantic/fix_plug_dependency_module_order.ex [row 82]`, 07-14 03:49; this escalation is 07-14 15:06), which added the `short_name` fallback so `plug(ApiVersion, …)` after `alias LifecycleApi.Plugs.ApiVersion` resolves. Probed the classifier's verbatim BEFORE against the live accepted rule: `match?` true, `fix/2` reorders `LifecycleApi.Plugs.ApiVersion` above `LifecycleApi.Router` correctly. The agent then reached the same conclusion, staged nothing, and the Gate emitted `:no_lib_change` — correct behaviour, zero value. Delete the log.

*Follow-up:* LD4 evidence: this is a rule re-suspected by a later pass of its own row after the fix landed. Seed the known-good marker from the commit trailer `[row N]`, not just from rule name.

*Appendix A:* yes — A puts it in the `:no_lib_change`/"rule already correct" cluster. A does not record that the fix came from the same row's earlier pass, which is the LD4-relevant detail.

#### row 95 — **FIX-HARNESS**  ·  `Credence.Semantic.UndefinedFunction`

The classifier emitted `DECISION=BUGFIX_RULE`, `RULE_NAME=Credence.Semantic.UndefinedFunction`, and then filled PROPOSED_NAME/PHASE/BEFORE/AFTER/ASSUMPTIONS each with a literal `===` line. `Cev.Classify.Parser.blank_to_nil/1` treats `"==="` as present, and `Cev.Classify.check_decision/2` for `:bugfix_rule` (lib/cev/classify.ex:106-114) validates ONLY that the rule name is in the closed set and resolves to a file — there is no before/after gate on the bugfix branch at all (the parse/`after`-mandatory gates are on `:potential_new_rule` only). So a spec with no reproduction sailed through and burned an 80-turn Claude Code session, which correctly did nothing → `:no_lib_change`. The row cost a full agent run and produced no artefact.

*Follow-up:* RE-QUEUE after the gate lands. Also FIX-CREDENCE (small): the underlying signal is real and still live — probed `Credence.Semantic.UndefinedFunction.match?/1` returns true on `undefined function send_resp/2 (expected NotificationPoller to define such a function or for it to be imported…)` while `fix/2` returns the source byte-identical. `Credence.Semantic` dispatches first-match (lib/semantic.ex:191 `Enum.find`) and UndefinedFunction ships no `should_report?/2` (unlike FixNimbleCsvDirectParse and FixPlugDependencyModuleOrder), so it consumes the diagnostic, reports an issue, fixes nothing, and no other rule gets a turn. Give it a decline guard.

*Appendix A:* no — A files 95 under `:no_lib_change` / "rule already correct". That is the Gate's label, not the cause: the row never had a spec to implement. A's cluster prescription ("no per-row action") would lose the classifier-gate bug.

#### row 97 — **DROP**  ·  `Credence.Semantic.FixNimbleCsvDirectParse`

The classifier's BEFORE is fabricated. It shows `NimbleCSV.define(CsvImporter.Parser, …)` alongside the bare `NimbleCSV.parse_string/2` call — but grepping the log, `NimbleCSV.define` appears nowhere in any of the three LLM solutions (only at 97.log:4339/4391, inside the classifier's own reply). The real source calls `NimbleCSV.parse_string/2` with no parser ever defined, so there is no target module to redirect to and the documented no-op is correct ("the file must contain exactly one `NimbleCSV.define/2` target"). Probed both shapes against the live rule: with the fabricated `define` line present it rewrites to `CsvImporter.Parser.parse_string` (i.e. it already does exactly what the bugfix asked for); without it, unchanged. The `[credence_fix] FixNimbleCsvDirectParse: fix returned IDENTICAL source` trace line at 97.log:2375 is what lured the classifier.

*Follow-up:* Feed into the C5 patch-drop item: the trace line that says a rule matched and changed nothing should distinguish "declined by design" (rule has `should_report?/2`) from "tried and failed".

*Appendix A:* yes on the DROP; A's reason ("rule already correct") is right but for the wrong reason — the point is that the classifier invented the input, not that the rule was recently fixed.

#### row 100 — **RE-QUEUE**  ·  `proposed new syntax rule fix_unclosed_function_call_paren (blocked by Credence.Syntax.NoKeywordIfBareInTuple)`

The agent built the rule and got 9/9 focused tests green; `mix test --exclude corpus` returned 7487 tests / 1 failure, which the agent correctly identified (and verified under `git stash`) as pre-existing: a crash in `NoKeywordIfBareInTuple.fix/1` on the `test/credence_pipeline_test.exs` "syntax phase runs before semantic" fixture. The harness's own re-run of the same command (152 s later, so it was the full-suite leg) went non-zero and the router discarded the whole clone. Verified repaired: `Credence.fix/1` on that exact fixture (`defmodule CrdPT_SyntaxFirst do\n  def broken(\n    :ok\n  end\nend`) now returns `%{code: <binary>, applied_rules: []}` with no raise, and the rule was rewritten wholesale at acceptance (ed06663). The proposal itself is a genuine open gap: credence ships `CloseUnclosedBrace` for `{` but nothing for `(`, and `fix_unclosed_function_call_paren` exists in neither repo. Nothing has to change before re-queueing.

*Follow-up:* FIX-HARNESS (shared with 119): `lib/cev/implement.ex:66` reports `String.slice(failures, 0, 400)` — the HEAD of mix output, i.e. compile warnings — while the LLM path already uses `trim/1` (last 3000 chars). Report the tail plus the ExUnit failure block, and record the exit code and WHICH of `focused_test/1`'s two `mix test` runs failed.

*Appendix A:* partly. A's re-queue call is right and A correctly names the `NoKeywordIfBareInTuple.fix/1` crash. A's other half — "pre-existing warnings in 4 sister test files" — is not the cause here: warnings never make `mix test` exit non-zero (no `--warnings-as-errors` in `run_mix_test`, none in either mix.exs); they merely occupy the first 400 chars of the give-up payload, which is what made them look causal.

#### row 116 — **DROP**  ·  `Credence.Syntax.NoPostfixIfExpression`

Two independent reasons. (1) The over-fire was real and is fixed. 116.log:672 shows it rewriting `hash_count = String.length(…String.replace_leading(line, fn c -> if c == ?#, do: " ", else: c end)))` into unparseable garbage (`hash_count = if c == ?#, do: " ", else: c end))), do: …, else: hash_count`) — the greedy `(.+)\s+if\s+` group swallowing a `fn` body. The accepted rule now requires `:error <- parse(line)` (the line must NOT parse on its own) plus a `faithful?/4` round-trip check that the rewrite re-parses to exactly `lhs = if <cond>, do: <expr>, else: lhs` with identical condition/expression ASTs. Probed the verbatim L294 line inside a non-parsing module: `analyze` → `[]`, `fix` → unchanged. (2) The `mutation_no_effect` rejection was correct and instructive: the classifier's BEFORE/AFTER are byte-identical AND multi-line (`if` on its own line), so the regression tests derived from it pass with or without the lib change — the single-line form at L294 is the only shape that reproduces.

*Follow-up:* Feed to the classifier gate proposed under row 95: a `BUGFIX_RULE` whose BEFORE == AFTER carries no reproduction and is the direct cause of `mutation_no_effect`. Requiring the classifier to emit the verbatim offending LINE (which the `credence_fix` trace already prints) instead of a re-minimized snippet would have saved this row.

*Appendix A:* yes on DROP. A calls it an "unproven bugfix"; the log shows the bug was proven (in the trace) but the classifier's minimization of it was not, which is the actionable distinction.

#### row 119 — **RE-QUEUE**  ·  `proposed new semantic rule fix_logical_or_in_guard`

High-value and still open. Probed current credence with `def check(x, y) when is_binary(x) || is_atom(y)`: the semantic phase logs `no rule matched diagnostic: "invalid expression in guard, || is not allowed in guards…"`, applies nothing, and returns the source unchanged — `fix_negation_in_guard` covers `!`→`not` but nothing covers `||`→`or` / `&&`→`and`. The rule exists in neither repo (the router discards the clone on give-up). The give-up itself is unexplained by the log: the agent's own `mix test --exclude corpus` was green (8012 tests, 0 failures) at 00:27:43 and the router logged `:cc_tests_red` at 00:27:52 — 9 s later, far too short for that suite, so the leg that failed was the focused one, after `canonicalize_fix_tests` (a no-op here: `credence.fix_tests` only handles `test/pattern/…`) and `normalize_test_heredocs` (revert-on-red by construction) ran.

*Follow-up:* FIX-HARNESS first (same defect as row 100): report the failure tail, the exit code, and which `mix test` leg failed, so a repeat is diagnosable. Note for the future rule: the diagnostic arrives with `position: 0` (no line), so it must not key on a line number.

*Appendix A:* no on the mechanism. A says the root cause is "pre-existing warnings in 4 sister test files fixed during Phase 4.2". The warning the payload actually cites — `test/semantic/no_exit_two_args_fix_test.exs:10` `defp fix(source, message, line \\ 1)` with all four call sites passing 3 args — is STILL present in /home/kamil/projects/credence_evolution today, and warnings cannot fail `mix test` anyway. A's RE-QUEUE verdict is right; its stated precondition ("already fixed") is not established.

#### row 123 — **DROP**  ·  `Credence.Syntax.NoPythonMultiReturn`

The reported over-fire was real, severe, and is now structurally impossible. 123.log:714 shows 12 lines of a multi-line call corrupted — `root_item,` → `{root_item, }`, `items_by_id,` → `{items_by_id, }`, `0,` → `{0, }`, and the same for the `orphan_item` call — turning a file with one unrelated parse error (`:queue.Queue{data: []}`) into one that fails at `near "'{'"`. The version live at the time (3d7df96) gated on a purely textual `has_bare_comma?(line)`; the accepted rule replaced that with `match?({:ok, _}, wrapped_line(line))`, and `wrapped_line/1` at lib/syntax/no_python_multi_return.ex:191 rejects unconditionally on `false <- String.ends_with?(trimmed, ",")`. Every one of the 12 damaged lines ends in a comma, so no depth-tracking desync can resurrect it. (I could not rebuild a faithful repro — the log truncates the 327-line module at 224 lines — but the guard is categorical, not heuristic.) The classifier also emitted BEFORE == AFTER again, so the agent had nothing to test against and staged test-file-only changes → `:no_lib_change`.

*Follow-up:* LD3 + LD4: staged entries were two test files only, the exact case LD3 is meant to accept as `verified_good`. And this is NoPythonMultiReturn's 5th re-suspicion (its rationale itself cites rows 59 and 50); the file carries 10 `bugfix(over_fire)` commits.

*Appendix A:* yes on DROP, but A's cluster label ("rule already correct") is wrong for this row: the classifier reported a genuine, reproduced corruption. It was fixed later, at acceptance — not correct at the time.

#### row 124 — **DROP**  ·  `proposed new pattern rule prefer_guard_over_nil_filter_in_for`

35 NEW corpus hits, 0 GONE, and the rule is unsound by design. Its own moduledoc says the point is to CHANGE behaviour — `for x <- l, do: if(c, do: v)` returns a list WITH nils, `for x <- l, c, do: v` returns a shorter list without them — which disqualifies a Pattern rule outright. Sampled 5 of the 35 hits from the corpus and every one is `for` used as a side-effecting loop whose result is discarded: jason/lib/codegen.ex:118 (`for <<byte <- binary>> do if … raise EncodeError end end`), libgraph/lib/graph/directed.ex:60 (`if … throw(:has_loop)`), cubdb/lib/cubdb.ex:1253 (`if Btree.alive?(old), do: :ok = Btree.stop(old)`), plus two compile-time macro loops — slugger/lib/slugger.ex:104, where the `if` body is a `defp` definition, and spark/lib/spark/dsl.ex:584. The last two also falsify the `@verified_dsl_safe` entry the patch added on the reasoning that "the rule only matches `for` comprehensions, which aren't valid DSL expressions". Nothing landed in either repo; delete 124.patch and 124.corpus.md.

*Follow-up:* Add `prefer_guard_over_nil_filter_in_for` to the classifier's rejected-over-fire list (H8). Hand slugger.ex:104 and spark/dsl.ex:584 to Phase 6.5's C14 DSL-safety scan as counter-examples: `for` at module body level is a compile-time macro loop, and a `@verified_dsl_safe` claim asserted by the authoring agent is not evidence.

*Appendix A:* yes — A prescribes drop + feed the name to the classifier's rejected list. A does not record the behaviour-changing-by-design defect or the falsified DSL-safety entry.

#### row 134 — **FIX-CREDENCE**  ·  `Mix.Tasks.Credence.FixTests (NOT Credence.Pattern.PreferSigilCharlist)`

PreferSigilCharlist's escaping is CORRECT — probed: `def f, do: 'say "hi"'` → `def f, do: ~c"say \"hi\""`, which parses. The red test was caused by the harness's pre-Gate canonicalization corrupting the fixture, and I reproduced it. `Mix.Tasks.Credence.FixTests.heredoc/1` at /home/kamil/projects/credence/lib/mix/tasks/credence.fix_tests.ex:246 is `defp heredoc(value), do: "\"\"\"\n" <> value <> "\"\"\""` — it splices the rule's raw output into a `"""` heredoc with no escaping of `\` or `#{`. Repro (scratch copy, `fix_file/1` called directly): the file is rewritten to `expected = """\n…~c"say \"hi\""\n"""`, which Elixir reads back as `"…~c\"say \"hi\"\"\n"` — backslashes consumed as heredoc escapes. That is byte-for-byte the give-up payload (`left: …~c\"say \\\"hi\\\"\"` vs `right: …~c\"say \"hi\"\"`). Fix: escape `\` and `#{` when emitting, or emit `~S"""` when the value contains either. This silently corrupts any fix test whose expected output contains a backslash — i.e. exactly the escaping-sensitive rules.

*Follow-up:* RE-QUEUE 134 after the fix. Reject the classifier's actual proposal: it asked to stop rewriting `'$end_of_table'` because "the correct rewrite is `:\"$end_of_table\"`" — that is wrong, `'$end_of_table'` in Elixir source is a charlist, so `~c"$end_of_table"` is the behaviour-preserving rewrite (still applied by the live rule; verified) and the atom form would change semantics. Also check `Credence.FixtureHealer.heal_dirs/0` (test/support/fixture_healer.ex:40) for the same class — it rewrites every file under test/{pattern,semantic,syntax} on EVERY `mix test` invocation, focused runs included.

*Appendix A:* no. A calls this "`PreferSigilCharlist` `~c\"say \\\"hi\\\"\"` escaping" and routes it to Phase 6 as a rule bugfix. The rule is fine; the bug is in credence's own fix-test canonicalizer, which is a wider blast radius than one rule. Keep it on the 6.5 worklist but re-point it at lib/mix/tasks/credence.fix_tests.ex.

#### row 137 — **DROP**  ·  `proposed new pattern rule no_missing_state_key_in_genserver`

Per-hit review of the single NEW hit: it is a false positive with a confidently false message. kayrock/lib/kayrock/client.ex:107 is flagged as "init returns a state map missing key `:cluster_metadata` … this will raise KeyError on every call" — but that init reads `state = %State{…}`, then returns `{:ok, %{state | cluster_metadata: cluster_metadata, correlation_id: 0}}`, i.e. the key IS set, in shipped working code. Mechanism, from the patch: `find_ok_map_in_body/1` matches `{:ok, {:%{}, _, entries}}`, and for map-update syntax `entries` is the single node `{:|, _, [state_var, [cluster_metadata: …, correlation_id: …]]}`, which `extract_map_keys/1` silently drops (it only matches `{{:__block__,_,[key]}, val}`). Key set comes back empty, so EVERY `state.X` access in the callbacks is "missing". Struct-based and update-based inits — the mainstream shape — are all mis-flagged. The corpus report also notes "(check-only — rule flags but applies no fix)", contradicting the rule's advertised auto-fix. 1 of 1 hit false → drop; delete 137.patch and 137.corpus.md.

*Follow-up:* The idea has a narrow core (literal-map init, single init clause, no `%{m | …}`, no struct). If it is ever re-queued, require map-update/struct handling and multi-clause init, soften the message off "guaranteed KeyError", and add kayrock/lib/kayrock/client.ex as a fixture.

*Appendix A:* yes — A prescribes exactly this per-hit review and the review lands on DROP. A did not prejudge the outcome.

### escalated 144–225

#### row 144 — **RE-QUEUE**  ·  `fix_reduce_with_halt (proposed; does not exist in credence or the sister)`

Not a bad rule — a bad implementation run. The target is a genuine crash-repair: I reproduced the classifier's BEFORE and `Enum.reduce` with a `{:halt, acc}` return dies with `no function clause matching` (the halt tuple becomes the next accumulator), while the `reduce_while` + `{:cont, _}` AFTER returns `{1, 90, 2}`. Credence still has no coverage: `no_reduce_while_without_halt` is the inverse direction and `prefer_reduce_while_with_halt_value` is the flag-in-accumulator shape. The agent died at turn 42 on a self-inflicted AST bug it had already diagnosed at step 70 — its `wrap_value/1` returned `{{:__block__, [], [:cont]}, n}` from a `Macro.postwalk/3` reducer, which Elixir reads as `{new_node, acc}`, so `{:cont, …}` was never wrapped; it also left `reduce_while_call?/1` unused (compile warning) and shipped an equivalence test whose BEFORE never halts, so the assertion was meaningless. The classifier notes 2 of 3 solve attempts in this row hit the identical bug, so the failure mode is frequent in the dataset.

*Follow-up:* Nothing has to change in the harness first. Add to the re-queue prompt: this is a REPAIR (before crashes on every halting input that isn't the last element; when halt fires on the last element `reduce` silently returns `{:halt, acc}`), so the equivalence test must use `mark_equivalence_unconstructible` or a repair-shaped before/after — not `assert_equivalent`.

*Appendix A:* No — Appendix A groups 144 under "Real bugs surfaced, unfixed" and says "144/55 likely drop". I disagree: the drop verdict was formed from the equivalence-red symptom, not the cause. The rule concept is sound and uncovered; only the implementation was broken.

#### row 145 — **DROP**  ·  `NoPythonMultiReturn (suspected over-fire on bare atoms in ETS option lists)`

Textbook LD3. The agent proved the suspicion false — `find_bare_comma_lines` skips `:ordered_set,`/`:public,` inside `[...]` because `compute_line_start_depths` counts the `[` delimiter, so those lines are at depth > 0. It then wrote two regression tests (an analyze test asserting `analyze(code) == []` on the verbatim `NoPythonMultiReturnOverFire` module, and a `confirm_fix(fix(input), input)` fix test), ran 61 focused and 8040 full-suite tests green, and the Gate discarded the whole thing with `REJECT: :no_lib_change` because only `test/syntax/no_python_multi_return_{analyze,fix}_test.exs` were staged. No credence defect exists; no patch was preserved.

*Follow-up:* Two: (1) the two regression tests are recoverable verbatim from 145.log around steps 44–47 — land them by hand so the fifth re-suspicion of this rule has a pinned answer; (2) this row is one of the five `NoPythonMultiReturn` re-suspicions that motivate LD4's known-good marker, and one of the eleven that motivate LD3's test-only-diff policy.

*Appendix A:* Yes — Appendix A puts 145 in the `:no_lib_change` cluster with "no per-row action" and names NoPythonMultiReturn as re-suspected ×5. It does not mention that the green regression tests are salvageable from the log.

#### row 150 — **DROP**  ·  `fix_ets_bare_concurrency_option`

4 hits, 4 false positives, and 2 of the 4 fixes actively break working code — I ran the extracted rule against the corpus files. broadway_dashboard/counters.ex:67 and nebulex stats.ex:91 are `:counters.new(n, [:write_concurrency])`, not ETS at all; `:counters.new/2` takes exactly that bare atom, and I verified the rule's rewrite `[{:write_concurrency, true}]` raises `ArgumentError: 2nd argument: invalid option in list`. phoenix_live_dashboard ets_info_component.ex:12-13 is a plain `@info_keys` list of `:ets.info/1` key names; the rule rewrites `:read_concurrency,` → `{:read_concurrency, true},` inside a data literal. Root cause: both `check/2` and `fix_patches/2` match any bare `:read_concurrency`/`:write_concurrency` atom anywhere in the AST — there is no test that it sits in the second argument of an `:ets.new/2` call. The moduledoc premise is also mis-dated: I verified `:ets.new(:t, [:set, :read_concurrency])` raises on this OTP too, so it is not an "OTP 27+" regression.

*Follow-up:* The underlying idea is real (bare concurrency atoms in `:ets.new/2` options do raise), so re-spec and re-queue: match only atoms that are elements of the list literal in argument 2 of an `:ets.new/2` call. Add `fix_ets_bare_concurrency_option` to the classifier's rejected-over-fire list for H8, with the mechanism ("leaf-atom match with no enclosing-call scope"), not just the name. Delete 150.patch/150.corpus.md.

*Appendix A:* Yes on the outcome — Appendix A lists it for per-hit review and the corpus.md default is DROP. Neither establishes the important part: this is not a harmless over-fire, the fix converts correct `:counters.new/2` calls into a runtime badarg.

#### row 162 — **DROP**  ·  `no_reraise_after_atom_catches`

1 hit, 1 false positive, and the fix silently deletes live error handling. I ran the extracted rule on tesla/lib/tesla/middleware/compression.ex: it flags the `try` at line 200 and emits one deletion patch that removes the clause `:error, {:data_error, _} = reason -> reraise Error, [reason: {:zlib, reason}], __STACKTRACE__` — after which structured zlib data errors escape as raw ErlangError instead of Tesla.Error. Root cause is a vacuous guard: `catch_all_reraise?/1` accepts the clause when `var_name(kind_var) == var_name(k)`, and `var_name/1` falls through to `nil` for anything that is not a variable, so on tesla the comparison is `nil == nil` for both the kind and the reason. The premise is independently false too: dropping a `kind, reason -> reraise …` catch-all is not behaviour-preserving when the preceding clauses only cover `:error`/`:exit`, and the real defect in the LLM shape is that `Kernel.reraise/3` is `reraise(exception, attrs, stacktrace)` — the repair is `:erlang.raise(kind, reason, __STACKTRACE__)`, not deletion.

*Follow-up:* Add `no_reraise_after_atom_catches` to the H8 rejected-over-fire list. If the shape is ever re-proposed, it must be re-specced as a repair to `:erlang.raise/3`, never a clause deletion, and any `f(a) == f(b)` guard whose `f` can return `nil` must be rejected in review. Delete 162.patch/162.corpus.md.

*Appendix A:* Yes on the outcome (per-hit review, corpus.md default DROP). It does not record that the preserved fix deletes a functioning catch clause in a real dependency, which is the reason this one must never be resurrected as-is.

#### row 169 — **RE-QUEUE**  ·  `fix_missing_paren_after_fn_end (proposed; gap still open in credence)`

The gap is real and still unfilled: I fed the classifier's BEFORE (`Task.async(fn -> … end` with no closing paren) through the live pipeline and got `Credence.Syntax.analyze/2 == []`, `fix_with_trace/2` returning the source byte-identical with `applied == []`, and the parse error `line 4: unexpected reserved word: near "end"` unrepaired. The two neighbours do not cover it — `NoUnclosedFnDelimiter` is `fn args -> body)` with the `end` missing, `CloseUnclosedFnDelimiter` is `end)` plus a stray `end` — exactly as the classifier's rationale claimed. The run did not fail on the merits: at step 41 of an 80-turn budget (23 turns used) the provider returned "The request was rejected because it was considered high risk" after a `mix run -e` whose heredoc contained deliberately malformed Elixir, and the agent stopped there with the scaffold assertion untouched — the give-up message quotes `left: "foo(bar)" / right: "baz(qux)"`, the placeholder the scaffold ships with.

*Follow-up:* FIX-HARNESS: the log records `agent done — subtype=success turns=23` and the Router files `gave_up: {:cc_tests_red, …}`, so a provider-side refusal is being booked as a substantive test failure. H9's environmental-failure triage must key on the refusal string (and on "turns used ≪ cap with the scaffold placeholders still present"), alongside the timeout/429 cases. Nothing else has to change before re-queueing.

*Appendix A:* Partly — Appendix A has 169 under "Implementer gave up — scaffold/hard: one retry each next run; drop on second failure", which matches RE-QUEUE. It attributes the failure to the 80-turn cap; the log shows the cap was never reached and an API refusal killed it at turn 23, so "drop on second failure" would be the wrong policy for this row until H9 lands.

#### row 178 — **DROP**  ·  `Credence.Semantic.UnusedVariable (suspected: two unused bindings on adjacent lines; over-fire on a delimiter diagnostic)`

Second LD3 instance and the agent's conclusion checks out on its face: the rule requires `severity: :warning` and a `variable "…" is unused` message, so the captured mismatched-delimiter diagnostic (severity `:error`) cannot match it; and the pipeline's right-to-left diagnostic ordering (highest column first) already handles `overrides` + `needs_user?` on adjacent lines without the "IDENTICAL source" bail-out. 42 focused tests, 6841 full-suite tests and the DSL-safety classification test all green, then `REJECT: :no_lib_change` on a single staged file, `test/semantic/unused_variable_test.exs`. No lib defect, no preserved patch.

*Follow-up:* Salvage the two regression tests from 178.log (steps ~78–80: the must-not-fire test using the verbatim delimiter diagnostic, and the two-unused-bindings fix test) and land them by hand. Otherwise this row is pure LD3 evidence.

*Appendix A:* Yes — Appendix A lists 178 in the `:no_lib_change` cluster with no per-row action, feeding LD3/LD4.

#### row 199 — **ACCEPT**  ·  `no_negative_step_in_string_slice`

6 hits split 3 true / 3 false, and the three true ones are genuine deprecations. On Elixir 1.20.2 I measured: `String.slice(s, 2..-1)` emits two warnings — the compile-time `2..-1 has a default step of -1, please write 2..-1//-1 instead` and the runtime `negative steps are not supported in String.slice/2, pass 2..-1//1 instead` — so archethic evm.ex:27 and :65 (`String.slice(encoded_result, 2..-1)`) and credo interpolation_helper.ex:274 (`String.slice(line, start..-1)` where `start = max(col_end - 1, 0)` is always ≥ 0) are true positives that break `--warnings-as-errors` today and become a hard error later. The other three are false: `-6..-1` and `-4..-1` have an inferred step of **+1**, and I confirmed `String.slice("hello world", -6..-1)` returns " world" with no warning at all — so blockscout address_view.ex:268, glific action.ex:583 and livebook session.ex:2937 are idiomatic suffix slices. The defect is one predicate: `bare_neg_one_range?/1` matches on the `-1` endpoint and ignores the start entirely. I ran the rule's `fix_patches/2` over all six files: every rewrite is a correct, minimal `..-1` → `..-1//1` and none changes behaviour, so worst case the un-narrowed rule emits no-op findings rather than corrupting anything. The classifier also reports all three solve attempts in this row hit the pattern in `split_edge/2`.

*Follow-up:* Narrow before applying: `bare_neg_one_range?/1` must decline when the range start is a negative integer literal (`{:-, _, [{:__block__, _, [n]}]}`), keeping non-negative literals and non-literal expressions. Then `git apply` 199.patch into lib/pattern/ (sister on the fresh `evolution` branch per Phase 9.2, or straight into credence), add a check-test fixture asserting `clean?` on `String.slice(s, -6..-1)`, run `mix credence.corpus` and confirm the NEW delta is exactly the two archethic lines plus credo:274, then `--update-snapshot` to pin them and `mix test` green. Also correct the moduledoc: the step default is 1.12-era, not "Elixir 1.19+", and the value returned today is still the suffix (with a warning), not "" as the rationale claims.

*Appendix A:* Neutral-to-wrong. Appendix A only prescribes "per-hit review", but the preserved 199.corpus.md heads the section "likely an OVER-FIRE → DROP" and that default is wrong here — half the hits are real deprecation sites in archethic and in credo, this repo's own dependency.

#### row 221 — **DROP**  ·  `prefer_float_cast_for_dynamic_multiplicand`

4 hits, 4 false positives, and the motivating diagnostic does not exist. All four sites are the idiomatic int→float coercion `Map.get(...) * 1.0`: image/options/vignette.ex:75-77 (`k1/k2/k3: Map.get(options, :kN, 0.0) * 1.0`) and image/palette.ex:350 (`mass = Map.get(counts, idx, 0) * 1.0`). I ran the extracted rule: `check/2` returns 3 and 1 issues respectively and `fix_patches/2` rewrites them to `:erlang.float(Map.get(...)) * 1.0` — a semantic no-op that swaps readable Elixir for an `:erlang` BIF call. The rationale claims the type-checker emits `incompatible types given to Kernel.*/2: float(), dynamic()` and that `--warnings-as-errors` therefore rejects compilation; I compiled `def a(item), do: Map.get(item, :k, 0) * 1.0` with `elixirc --warnings-as-errors` on Elixir 1.20.2 and it is clean, because `dynamic()` is compatible with `float()`. There is no gap next to `PreferErlangFloat` to close.

*Follow-up:* Add `prefer_float_cast_for_dynamic_multiplicand` to the H8 rejected-over-fire list. Delete 221.patch/221.corpus.md. The wider lesson belongs in the pre-implementer premise check (see cluster findings).

*Appendix A:* Yes on the outcome (per-hit review, corpus.md default DROP). Appendix A does not note that the rule's stated motivation is a fabricated compiler diagnostic, which is the strongest reason it can never be resurrected.

#### row 225 — **RE-QUEUE**  ·  `prefer_pattern_match_for_struct_field_validation (proposed)`

Genuine scaffold give-up at the cap — `agent done — subtype=error_max_turns turns=81`, 251 tool steps, ~$56 of budget, and the last thing it wrote was a `mark_equivalence_unconstructible` opt-out. The rewrite itself (`if c1 != c2 do raise end` → two clauses binding the shared field plus a catch-all raise) is behaviour-preserving on the shown shape and the check/fix tests were converging. What burned the budget is a real, reproducible defect in credence's equivalence harness, not the rule: `test/support/behaviour_equivalence.ex:312 compile_module!/2` does `String.replace(source, "defmodule Money", "defmodule Eqv_Before_N", global: false)`, renaming only the header, so every `%Money{}` literal in the body still points at the original name. I reproduced it: `error: Money.__struct__/1 is undefined, cannot expand struct Money … cannot compile module Eqv_Before_1`. Any rule whose example defines and then uses its own struct is therefore untestable for equivalence, exactly as the agent's opt-out docstring says.

*Follow-up:* FIX-CREDENCE first, then re-queue: `test/support/behaviour_equivalence.ex:312` — rename all references to the module, not just the `defmodule` header (word-boundary global replace, or inject `alias Eqv_Before_N, as: Money`), and add a positive control that a struct-defining before/after pair now compiles and compares. Until that lands a retry will hit the same wall and burn another 80 turns. Note the interaction with Phase 8.2/H4: this bug is manufacturing `mark_equivalence_*` rules that H4 then has to insure against.

*Appendix A:* Partly — Appendix A says "one retry each next run; drop on second failure", and RE-QUEUE matches. It does not identify the blocker, so a plain retry would fail identically and the "drop on second failure" rule would then discard a rule that was never actually testable.

### behaviour_diverged (all 13)

#### row 1 — **RE-QUEUE**  ·  `no_hallucinated_map_empty (proposed; semantic)`

Real gap: `Map.empty?/1 is undefined or private` appears 10x in the log and is listed under REMAINING_ISSUES (UndefinedFunction matched, produced no fix). The probe killed it for a battery reason, not a behaviour reason: I re-ran Cev.Equiv.extract + credence.equiv's classify/5 offline and reproduced the exact log verdict — before raises UndefinedFunctionError on 44/44 battery inputs, after (`map_size(map) == 0`) raises BadMapError on 44/44, so `repair?/1` fails ONLY its `Enum.any?(after == {:ok,_})` clause. Adding `%{}` to the battery flips the same pair to REPAIR(strict).

*Follow-up:* Blocked on the equivalence-battery fix (see cluster findings); dedupe against row 18, which proposes the identical target and fix under the name `no_map_empty`. Home is a sibling of lib/semantic/no_map_has.ex, or a new UndefinedFunction replacement type (the existing {:rename,…}/{:literal,…} forms cannot express `f(x)` -> `expr(x) == 0`).

*Appendix A:* Agrees on the class (before = UndefinedFunctionError) but is wrong on the mechanism. It says the probe is vacuous because "any working after looks divergent"; in fact credence.equiv already has a REPAIR verdict for exactly this shape (lib/mix/tasks/credence.equiv.ex:115-133) and it was denied because the after ALSO raised on 100% of the battery. The defect is the untyped battery, not the gate's trichotomy.

#### row 7 — **RE-QUEUE**  ·  `no_hallucinated_float_coerce (proposed; semantic)`

Real gap: `warning: Float.coerce/1 is undefined or private` at 7.log:1021, three call sites (`Keyword.get(opts, :bucket_capacity, 5.0) |> Float.coerce()`), unfixed. Same battery mechanism as row 1: before UndefinedFunctionError 44/44, after `:erlang.float(x)` ArgumentError 44/44 because the battery contains only lists and binaries — no bare numbers. Extended battery -> REPAIR(strict). Note Credence.Pattern.PreferErlangFloat fired in this row on unrelated code; it does not cover the hallucinated call.

*Follow-up:* Blocked on the battery fix. Cheapest of the 13 to land: a one-line entry `{"Float", "coerce", 1} => {:rename, ":erlang", "float"}` in @qualified_replacements, lib/semantic/undefined_function.ex.

*Appendix A:* Same as row 1 — right about the class, wrong about the mechanism.

#### row 12 — **DROP**  ·  `no_hallucinated_naive_datetime_accessor (proposed; semantic)`

Superseded. The target shipped: /home/kamil/projects/credence/lib/semantic/fix_hallucinated_naive_datetime_accessor.ex covers minute/hour/day/month -> `dt.<field>`. The one residual piece, `NaiveDateTime.day_of_week/1` -> `Date.day_of_week(dt)`, is *deliberately declined* by the shipped rule's moduledoc (no `:day_of_week` field on the struct; the `starting_on` week convention cannot be read off the call site) — a recorded decision, not an open gap. The log's own REMAINING_ISSUES block (12.log:2336) confirms all five diagnostics were unfixed at the time.

*Follow-up:* None for the row. But preserve one piece of evidence from its twin: committed/12 proposed the SAME rule and got through the probe only because its ===AFTER=== block ends with `}` instead of `end`, so Code.string_to_quoted failed, Cev.Equiv.extract returned :error and check/2 returned :skipped. A classifier typo is what let the correct rule be built while the well-formed spec here was killed.

*Appendix A:* Not covered — Appendix A lumps 12 in with the other twelve and does not note that the rule has since shipped, nor that the twin passed the probe by way of a malformed spec.

#### row 18 — **RE-QUEUE**  ·  `no_map_empty (proposed; semantic)`

Same target as row 1 with a minimal spec (`if Map.empty?(map)` -> `if map_size(map) == 0`). `Map.empty?/1 is undefined or private` 7x in the log, unfixed. Reproduced: before UndefinedFunctionError 44/44, after BadMapError 44/44 — repair? denied solely by the after-succeeded clause; typed battery -> REPAIR(strict).

*Follow-up:* Blocked on the battery fix; merge with row 1 before re-queueing so the next run does not build the rule twice under two names.

*Appendix A:* Same as row 1 — right about the class, wrong about the mechanism.

#### row 31 — **FIX-HARNESS**  ·  `no_hallucinated_mapset_empty (proposed; semantic)`

Carrying the primary harness defect here because this row is its minimal reproduction: single-expression before/after (`MapSet.empty?(set)` -> `MapSet.size(set) == 0`), diagnostic present 4x and unfixed, sibling rule fix_hallucinated_mapset_any.ex already in credence. Mechanism, verified offline: the default battery is @all_dims = [term_lists, signed_integers, stability_lists, + 3 string dims] and every one of its 44 values is a list or a binary (`signed_integers` returns LISTS of integers, not integers). So before raises UndefinedFunctionError 44/44 and after raises FunctionClauseError 44/44, and repair?/1 — which requires `Enum.any?(after == {:ok,_})` — can never be satisfied for any repair whose fixed code needs a map, struct, MapSet, %Task{} or bare integer argument. Files: /home/kamil/projects/credence/test/support/equivalence_inputs.ex (the battery) and /home/kamil/projects/credence/lib/mix/tasks/credence.equiv.ex:66 (@all_dims), :100-126 (classify/5), :131-134 (repair?/1).

*Follow-up:* RE-QUEUE after the fix. This is exactly Phase 6.2's C2.1-rest item ("add the missing battery dimensions: maps, keyword_lists, tuples, mixed_numeric") — extend it with structs (%Date{}/%DateTime{}/%NaiveDateTime{}/%Task{}) and MapSet; verified that battery alone flips 10 of these 13 rows to REPAIR(strict).

*Appendix A:* Agrees the row is vacuous, disagrees on why, and its prescribed remedy is unsafe — see cluster findings.

#### row 33 — **FIX-HARNESS**  ·  `no_deprecated_system_stacktrace (proposed; semantic)`

A genuinely different sub-class, and Appendix A's "harness-frame variant" label understates it. The before COMPILES and RETURNS on every input: before_raised = 0/44, after_ok = 44/44. `System.stacktrace/0` still exists (it only emits `is deprecated. Use __STACKTRACE__ instead`, 4x in the log, unfixed) and returns `[]`, so before = {:ok, {:error, {%BadFunctionError{term: []}, []}}} and after = the same tuple with a 7-frame `__STACKTRACE__`. Every frame in that diff belongs to the probe itself (:erl_eval.do_apply/try_clauses, :elixir.eval_external_handler, Credence.BehaviourEquivalence.run_outcome/eval_outcome, ExUnit.CaptureIO.do_with_io). Neither clause of repair?/1 is even in play, and no battery change can fix it: the strict `===` in classify/5 compares a stacktrace, which is environment-dependent by construction.

*Follow-up:* Fix in /home/kamil/projects/credence/test/support/behaviour_equivalence.ex run_outcome/eval_outcome (or in classify/5): normalize stacktrace-shaped values (lists of {mod, fun, arity, loc}) before comparison, or strip frames belonging to erl_eval/elixir eval/Credence.BehaviourEquivalence/ExUnit. Then RE-QUEUE — but the rule needs a scope guard the classifier did not mention: `__STACKTRACE__` is only legal inside a try/rescue/catch/after clause, so rewriting a `System.stacktrace()` that sits outside one trades a deprecation warning for a hard compile error.

*Appendix A:* Partly. It is right that 33 is a separate variant and right to name it in LD2, but "harness-frame-only term diff" is a coincidence of running under eval — the substance is that the fix's entire purpose is to change this value (from [] to a real trace), so a strict term comparison can never pass it.

#### row 105 — **DROP**  ·  `no_bang_in_with_pattern (proposed; semantic)`

TRUE POSITIVE — the probe was right and Appendix A is wrong. The direction is reversed: before = {:raise, WithClauseError}, after = {:raise, UndefinedFunctionError}. The proposed fix rewrites `File.stream!(path)` (exists) to `File.stream(path)`, which does NOT exist — verified on this machine's Elixir 1.20.2, `function_exported?(File, :stream, 1) == false`; File exports only stream!/1,2,3. Building this rule would have turned a runtime error into a compile error. Independently fatal: the row's failure is a pure runtime WithClauseError (13 identical failures, 105.log:1816-2044) with NO compiler diagnostic — grepping the log for "never match" finds nothing — so a Semantic-phase rule, which is driven off diagnostics, could never fire on it anyway. The LLM self-healed it at 105.log:2645 by switching to `case File.stream!(path) do`.

*Follow-up:* Make row 105 the mandatory positive control for LD2: any relaxation of the probe that lets this row through is wrong. Verified that the two fixes I recommend (typed battery, tolerant repair?/1) both leave it DIVERGES (after_ok = 0/56 even with the extended battery). The underlying idiom — `with {:ok, x} <- <bang fn>(...)`, whose else-branch is dead — is a legitimate future Pattern-phase target, but only with a repair that does not invent an API.

*Appendix A:* NO. Appendix A asserts all 13 are `before = raise UndefinedFunctionError` by construction. Here the before is WithClauseError and it is the AFTER that raises UndefinedFunctionError. This row is not vacuous, it is a correct kill, and re-queueing it as Appendix A prescribes would push a broken rule back into the pipeline.

#### row 106 — **RE-QUEUE**  ·  `no_datetime_accessor_as_function (proposed; semantic)`

Real gap: `DateTime.year/1`, `.month/1`, `.day/1`, `.hour/1` all `is undefined or private`, all four listed unfixed in REMAINING_ISSUES (lines 141-144 of the row's source). Same battery mechanism: before UndefinedFunctionError 44/44, after (`dt.year` etc.) BadMapError 44/44 because the battery contains no map or struct; adding ~U[...] flips it to REPAIR(strict).

*Follow-up:* Blocked on the battery fix. Home is the existing hallucinated-accessor family — lib/semantic/fix_hallucinated_naive_datetime_accessor.ex and lib/semantic/fix_hallucinated_calendar_iso_accessor.ex share one Sourceror anchored-rewrite skeleton (match on the exact `Mod.fun/1 is undefined or private` prefix, rewrite only at the diagnostic's line/column, no-op on aliased/piped/captured spellings); this is a DateTime-flavoured copy.

*Appendix A:* Same as row 1 — right about the class, wrong about the mechanism.

#### row 107 — **RE-QUEUE**  ·  `no_hallucinated_date_to_tuple (proposed; semantic)`

Real gap: `Date.to_tuple/1 is undefined or private` 3x, listed unfixed (line 109). Same battery mechanism: before UndefinedFunctionError 44/44, after `{d.year, d.month, d.day}` BadMapError 44/44; with ~D[...] in the battery it is REPAIR(strict).

*Follow-up:* Blocked on the battery fix. Prefer the stdlib target over the classifier's field triple: `Date.to_erl/1` exists and returns exactly {year, month, day}, so this collapses to a one-line entry `{"Date", "to_tuple", 1} => {:rename, "Date", "to_erl"}` in lib/semantic/undefined_function.ex instead of a whole new rule.

*Appendix A:* Same as row 1 — right about the class, wrong about the mechanism.

#### row 162 — **RE-QUEUE**  ·  `fix_hallucinated_task_stop (proposed; semantic)`

Real gap: `Task.stop/2 is undefined or private (line 28)` in REMAINING_ISSUES. Same battery mechanism: before UndefinedFunctionError 44/44, after `Task.shutdown(task, :brutal_kill)` FunctionClauseError 44/44 (no %Task{} in the battery); with a real Task.async/1 value in the inputs it is REPAIR(strict).

*Follow-up:* Blocked on the battery fix. One-line entry `{"Task", "stop", 2} => {:rename, "Task", "shutdown"}` in lib/semantic/undefined_function.ex; distinct from the shipped Credence.Pattern.FixTaskShutdownBrutalKill, which fixes the :brutal atom, not the function name. Bookkeeping: behaviour_diverged/162 and escalated/162 (`no_reraise_after_atom_catches`, 1 corpus hit, with .patch/.corpus.md) are different passes over the same dataset row — do not conflate them in the ledger.

*Appendix A:* Same as row 1 — right about the class, wrong about the mechanism.

#### row 164 — **RE-QUEUE**  ·  `no_hallucinated_task_pid_fn (proposed; semantic)`

Real gap: `Task.pid/1 is undefined or private` 9x in the log, unfixed at lines 47 and 53. Same battery mechanism: before UndefinedFunctionError 44/44, after `Process.exit(task.pid, :kill)` BadMapError 44/44; with a real %Task{} it is REPAIR(strict).

*Follow-up:* Blocked on the battery fix. This is the lowest-risk of the thirteen: lib/semantic/fix_task_ref_field_access.ex and lib/semantic/fix_task_id_field_access.ex are already shipped for the sibling fields, so it is the same rule with ref -> pid, including the existing decline list (&Task.pid/1 captures, piped, Elixir.-prefixed, alias-as-Task).

*Appendix A:* Same as row 1 — right about the class, wrong about the mechanism.

#### row 185 — **FIX-HARNESS**  ·  `no_hallucinated_datetime_valid (proposed; semantic)`

A SECOND, independent harness defect, and Appendix A's "by construction" claim is false here. The before does NOT raise on every input: `Enum.all?(list, &DateTime.valid?/1)` short-circuits to true on an empty list, so 3 of 44 battery inputs give before === after === {:ok, true}. Counters: before_raised 41/44, after_ok 27/44. So repair?/1 fails its FIRST clause (`Enum.all?(before raised)`), and classify/5 reports the next disagreeing pair, input=[1] — precisely the log line. Fix: make repair? ignore pairs that already agree — `Enum.all?(pairs, fn {_, ob, oa} -> match?({:raise,_}, ob) or ob === oa end)`. Verified this alone flips 185 to REPAIR on the UNCHANGED battery, and verified it does not rescue row 105 (after_ok = 0). File: /home/kamil/projects/credence/lib/mix/tasks/credence.equiv.ex:131-134.

*Follow-up:* RE-QUEUE after the predicate fix (`DateTime.valid?/1 is undefined or private` appears 6x, unfixed). Also record the inconsistency this exposes: the sibling proposal `DateTime.info?/1` -> `match?(%DateTime{}, x)` from committed/185 has the IDENTICAL repair, passed the probe as REPAIR because its call is not wrapped in an Enum.all?, and shipped as lib/semantic/no_hallucinated_datetime_info.ex. One rule family, two opposite verdicts, decided by whether the exemplar happens to wrap the call in a short-circuiting combinator.

*Appendix A:* NO on the stated mechanism. Appendix A says the before raises UndefinedFunctionError "by construction"; it raises on only 41 of 44 inputs, and it is that gap — not the after — that denies REPAIR. LD2 as written would rescue this row for the wrong reason and would not fix the predicate that is actually broken.

#### row 205 — **RE-QUEUE**  ·  `fix_hallucinated_make_tuple_arity (proposed; semantic)`

Real gap: `warning: :erlang.make_tuple/1 is undefined or private. Did you mean: make_tuple/3, make_tuple/2` at 205.log:631 — the compiler even names the fix. Same battery mechanism, and this row is the sharpest illustration of it: the repair `Tuple.duplicate(nil, capacity)` needs a bare integer, and although the battery has a dimension called `signed_integers` it returns LISTS of integers ([[], [0], [1,2,3], ...]), so after raises ArgumentError 44/44. Adding the scalars 0/1/5 flips it to REPAIR(strict). The classifier's own rationale already said "REPAIR — before never compiles"; the probe disagreed only because of the input shapes.

*Follow-up:* Blocked on the battery fix. While re-queueing, note a second uncovered target in the same row's later attempts: `undefined function setelement/3` (an Erlang BIF that is not auto-imported in Elixir), also listed unfixed and also absent from undefined_function.ex's tables — repair is `put_elem/3` or `:erlang.setelement/3`.

*Appendix A:* Same as row 1 — right about the class, wrong about the mechanism, and it misses that this row's blocker is the scalar/list shape of the battery rather than the presence of a dimension.

### classifier_errors (all 52)

#### row 1 — **RE-QUEUE**  ·  `Credence.Pattern.RemoveUnreachableClausesAfterCatchall (live, credence/lib/pattern/)`

Log shows `RemoveUnreachableClausesAfterCatchall: check found 1 issue(s), running fix...` then `fix returned IDENTICAL source` — a real detect-without-fix, but `lib/pattern.ex:158` drops no-op fixes from `applied`, so the rule can never be in the closed set. I could not reproduce on the duplicate-`defp` shape (current rule fixes it, `applied=[{RemoveUnreachableClausesAfterCatchall,1}]`), so the residual gap needs the row's real source.

*Follow-up:* FIX-CREDENCE lib/pattern.ex:158 — record `{rule, :no_op}` in the trace instead of silently dropping it (this is docs/16 C5); nothing else needs to change before re-queue

*Appendix A:* not covered — Appendix A only gives the cluster's error-code counts

#### row 6 — **DROP**  ·  `no_function_in_module_attribute (deleted in 4.6c)`

2 of 3 `APPLIED_RULES` lines were lost to Logger's 8096-byte truncation and the third was `[]`, so BUGFIX was not offered; the model answered anyway with `lib/semantic/no_function_in_module_attribute.ex` (file-path form). That rule was deleted in Phase 4.6c as `delete-duplicate` of `Credence.Semantic.FixFunctionInModuleAttributeInlineUsages`, so the report is moot.

*Follow-up:* FIX-HARNESS — `Cev.Classify.Parser.rule_name/1` must normalise `lib/<phase>/<name>.ex` and `<phase>/<name>` to `Credence.<Phase>.<CamelCase>`

*Appendix A:* not covered per-row; its `decision_not_offered` count of 6 is correct

#### row 7 — **RE-QUEUE**  ·  `Credence.Semantic.NoRescueInException (live)`

The rule matched the diagnostic and changed the source in attempt 2/3, but both of those attempts' `APPLIED_RULES` lines were truncated away, so the closed set held only attempt 1's two rules. The claim (fix introduces unreachable `catch` clauses) is plausible but I could not reproduce it — a plain `rescue e in RuntimeError` compiles and draws no diagnostic.

*Follow-up:* Nothing to change first — H12 (commit 60ce2c4) already routes the closed set through the untruncated sidecar

*Appendix A:* not covered

#### row 10 — **DROP**  ·  `Credence.Semantic.NoHallucinatedMapReduce (credence_evolution only)`

Same truncation loss (2 of 3 AR lines); the rule did match and change source. docs/18 already dispositions this rule `salvage-small-fix`, so the row adds no new decision.

*Follow-up:* Fold the row's extra detail — the fix leaves a deprecated `Map.size/1` behind, failing `--warnings-as-errors` — into that salvage item

*Appendix A:* not covered

#### row 20 — **DROP**  ·  `no_process_send_after_with_variable_infinity (deleted in 4.6c)`

All three `APPLIED_RULES` lines survived here; the named rule genuinely never fired, and the model was reaching into the full rule index for an under-fire report. The rule was deleted in 4.6c as `delete-implementation-dead`.

*Appendix A:* not covered

#### row 22 — **DROP**  ·  `no_defp_qualified_name (deleted in 4.6c)`

A Syntax under-fire: `defp Keyword.get_lazy(...)` never triggered the rule, and Syntax rules have no `check`, so an under-firing syntax rule leaves zero trace and can never enter the closed set. The rule was deleted in 4.6c as `delete-implementation-dead`.

*Appendix A:* not covered

#### row 23 — **RE-QUEUE**  ·  `Credence.Pattern.RemoveUnreachableClausesAfterCatchall (live)`

Identical to row 1 — `check found 1 issue(s)` then `fix returned IDENTICAL source`, invisible to the closed set via lib/pattern.ex:158. My repro of the duplicate whole-`defp` case now fixes cleanly, so the surviving gap is shape-specific.

*Follow-up:* FIX-CREDENCE lib/pattern.ex:158 (record no-op fixes); re-queue afterwards

*Appendix A:* not covered

#### row 27 — **DROP**  ·  `Credence.Syntax.NoPythonMultiReturn (live)`

All three `APPLIED_RULES` lines were truncated away (the log does show `syntax done. Applied: [FixElsifInIfChain(1), NoBareAtomInGenserverStartLink(1), NoPythonMultiReturn(1)]`), so the closed set was empty. The reported over-fire — `:n,` → `{:n,}` inside a bracketed `defstruct` list — no longer reproduces: `Credence.Syntax.NoPythonMultiReturn.analyze/1` returns `[]` on that shape, the accepted version carries a defstruct guard.

*Follow-up:* FIX-HARNESS name normalisation (the model emitted `syntax/no_python_multi_return`); also note `NoBareAtomInGenserverStartLink` corrupted `GenServer.start_link(m, cfg, server_opts)` → `[name: server_opts]` in the same trace — worth a separate look

*Appendix A:* not covered

#### row 28 — **FIX-HARNESS**  ·  `no_pipe_into_arithmetic_operator (credence_evolution only)`

The final error is `{:bad_decision, "BUGFIX_RULE\n===RULE_NAME===syntax/no_pipe_into_arithmetic_operator"}` — the model wrote the next marker on the same line as the decision value, and `Cev.Markers.split/1` requires a marker alone on its line, so the whole tail was swallowed into DECISION. All three AR lines were genuinely `[]` (the source never parsed past the pipe error), so BUGFIX was correctly unavailable.

*Follow-up:* Make the marker parser accept `===KEY===<value>` on one line; the rule report itself is moot (docs/18 dispositions the rule `rebuild-later-from-catalogue`)

*Appendix A:* yes on the count (1 `bad_decision`); the mechanism is not covered

#### row 38 — **DROP**  ·  `Credence.Semantic.NoProcessSendAfterInfinity (credence_evolution only)`

2 of 3 AR lines truncated; the rule did match and change source in the lost attempts. docs/18 dispositions it `rebuild-later-from-catalogue` (implementation dead, fix corrupts working code) and the module is to be deleted, so the bug report has no target.

*Appendix A:* not covered

#### row 49 — **FIX-HARNESS**  ·  `no_after_or_rescue_in_case (deleted in 4.6c)`

Cleanest evidence of the normalisation bug: attempt 1 emitted the bare snake name `no_after_or_rescue_in_case`, which `Parser.rule_name/1` turned into `:"Elixir.no_after_or_rescue_in_case"` — a name that cannot match anything. The prompt's own `## Existing rule index` teaches the `<phase>/<name>` spelling while the gate demands module atoms.

*Follow-up:* After the normalisation fix, DROP the rule report — the rule was deleted in 4.6c as `delete-duplicate` of `Credence.Semantic.FixAfterOrRescueInCase`

*Appendix A:* partially — Appendix A names "name normalisation" as a candidate cause; this row proves it, but it accounts for only 9 of 52 rows

#### row 54 — **FIX-CREDENCE**  ·  `Credence.Pattern.NoMapKeysOrValuesForIteration (live, credence/lib/pattern/no_map_keys_or_values_for_iteration.ex:374)`

REPRODUCED LIVE: `Credence.Pattern.fix/2` on `if Enum.all?(Map.values(state.queues), &:queue.is_empty/1) do ... end` raises `FunctionClauseError` in `rebuild_call/2` — its two clauses cover `{name,_,ctx} when is_atom(ctx)` and `{{:., _, [{:__aliases__,_,mod}, func]}, _, []}`, but an Erlang module capture is `{:__block__, _, [:queue]}`, matching neither. The exception kills the whole fix script (exit=1), discarding every earlier syntax/semantic fix and emitting no `APPLIED_RULES` at all — which is why this row's closed set was empty and BUGFIX was never offered.

*Follow-up:* Add a catch-all `rebuild_call/2` clause returning the AST unchanged; separately, credence C6 (per-rule crash isolation) would have contained the blast radius

*Appendix A:* not covered — Appendix A files this row only as one of the 6 `decision_not_offered`

#### row 59 — **RE-QUEUE**  ·  `Credence.Pattern.NoRedundantAssignment (live)`

All three AR lines lost to truncation → empty closed set; the model answered with `lib/pattern/no_redundant_assignment.ex`. Its report is specific and checkable (the rule strips a trailing bare `ref` return whose value differs from the preceding `Process.send_after/3` call, changing the return type) but needs the row's real source to confirm.

*Follow-up:* FIX-HARNESS name normalisation; re-queue once H12's sidecar is exercised

*Appendix A:* not covered

#### row 65 — **FIX-CREDENCE**  ·  `Credence.Semantic.NoBareNamesInSpec (live, credence/lib/semantic/no_bare_names_in_spec.ex)`

Same live defect as row 90, on a different shape: the rule matched `type product_map/0 undefined` and produced only reformatting. Its `fix/2` only rewrites bare names sitting as top-level args of the spec's function call; anything nested is left alone while the rule still claims the diagnostic, so the compile error survives every pass.

*Follow-up:* Fix with row 90 as the primary reproduction; 2 of 3 AR lines were also truncated here, already addressed by H12

*Appendix A:* not covered — Appendix A flags only row 90 for this rule; row 65 is the same bug and should join it

#### row 67 — **DROP**  ·  `fix_python_format_in_string_interpolation (deleted in 4.6c)`

Syntax under-fire on `"#{remaining_cents:02d}"`; the rule never fired so it could never be in the closed set. Deleted in 4.6c as `delete-implementation-dead`.

*Appendix A:* not covered

#### row 69 — **DROP**  ·  `Credence.Semantic.NoRemoteFunctionInGuard (credence_evolution only — NOT in credence)`

The bug is REAL and fully evidenced: the fix emitted `do: if(String.length(title) > 0, :do => :ok, :else => {:error, :empty_title})`, which I verified is a genuine `syntax error before: '=>'`, and the harness's own compile gate reverted it (`fix broke compilation — reverting`). But the module is not in credence and docs/18 already dispositions it `rebuild-later-from-catalogue` (delete the file, keep only `match?/1` + `to_issue/1`), so there is no live code to repair. It landed in classifier_errors purely because attempt 2's `APPLIED_RULES` line was truncated away by the giant reorder diff.

*Follow-up:* Amend FAILURE_MODE_CATALOGUE entry #11 / the docs/18 verdict with this third corruption path (unparseable `:do =>` output), so the rebuild does not repeat it; the Phase 6.5 worklist item as written points at a module scheduled for deletion

*Appendix A:* NO — Appendix A says "salvage row 69's rationale as a concrete rule bug → Phase 6 worklist". The bug is real, but the rule is not in credence and is already dispositioned for deletion, so the salvage belongs in the catalogue, not on a bugfix worklist

#### row 77 — **DROP**  ·  `fix_python_format_in_string_interpolation (deleted in 4.6c)`

Same under-fire as row 67, on `#{a:>08x}` and a `~s(~2.16.0b)` sigil; the rule never fired. Deleted in 4.6c as `delete-implementation-dead`.

*Appendix A:* not covered

#### row 87 — **DROP**  ·  `no_function_in_module_attribute (deleted in 4.6c)`

The rule matched and changed source, but 2 of 3 AR lines were truncated so it never reached the closed set. The report (removes `@default_clock fn -> ... end` and leaves the `@default_clock` references) is accurate, and 4.6c already deleted the rule as `delete-duplicate` of `Credence.Semantic.FixFunctionInModuleAttributeInlineUsages`.

*Follow-up:* Sanity-check that the surviving `FixFunctionInModuleAttributeInlineUsages` does inline the usage sites — three rows (6, 87, 88) hit this exact failure

*Appendix A:* not covered

#### row 88 — **DROP**  ·  `no_function_in_module_attribute (deleted in 4.6c)`

Duplicate of rows 6 and 87 — same `@default_clock` failure, same deleted rule, same truncation loss (2 of 3 AR lines).

*Appendix A:* not covered

#### row 90 — **FIX-CREDENCE**  ·  `Credence.Semantic.NoBareNamesInSpec (live, credence/lib/semantic/no_bare_names_in_spec.ex)`

REPRODUCED LIVE against credence HEAD. `match?/1` claims `type non_binary/0 undefined`, but `fix/2` returns byte-identical source whenever the bare name is not a top-level spec argument: `@spec parse(String.t() | non_binary) :: map` → NO-OP (row 90's exact shape), `@spec parse([bare_thing]) :: map` → NO-OP, `@spec parse(binary()) :: bare_ret` → NO-OP; only `@spec parse(sub_list) :: map` is fixed (→ `sub_list :: any()`). Because Semantic records `{rule, 1}` even for a no-op (lib/semantic.ex:152), the rule consumes the diagnostic and the compile error survives every pass.

*Follow-up:* Extend `fix_spec_body/2` to walk into `|` unions, list/tuple/map type terms and the return position; add the three no-op shapes as regression tests. (The row reached classifier_errors only because attempt 3's AR line was truncated — H12 fixes that.)

*Appendix A:* yes — Appendix A calls row 90 a concrete rule bug for the Phase 6 worklist, and it is; I add the exact boundary (nested-position bare names) and a reproduction

#### row 95 — **FIX-HARNESS**  ·  `Credence.Pattern.NonGroupedClauses (live)`

Both failure modes in one row: attempt 1 emitted `pattern/non_grouped_clauses` → `:"Elixir.pattern/non_grouped_clauses"`, attempt 2 emitted `Credence.Semantic.NonGroupedClauses` — right rule, wrong phase segment. `Parser.rule_name/1` does `:"Elixir.#{raw}"` with no normalisation and no phase-tolerant lookup. The rule really did fire and no-op (`NonGroupedClauses: check found ... fix returned IDENTICAL source`).

*Follow-up:* Normalise `<phase>/<snake>` → `Credence.<Phase>.<CamelCase>` and resolve by basename when the phase segment is wrong; then RE-QUEUE the row for the NonGroupedClauses no-op

*Appendix A:* partially — this is the "name normalisation is broken" hypothesis, confirmed

#### row 99 — **RE-QUEUE**  ·  `Credence.Semantic.FixNimbleCsvDirectParse (live)`

The log directly shows `FixNimbleCsvDirectParse: matched diagnostic, running fix...` then `fix returned IDENTICAL source` — a claimed-but-unfixed diagnostic — yet 2 of 3 AR lines were truncated so the rule never entered the closed set. I could not reproduce outside a workspace with NimbleCSV as a dep (my probe produced a different diagnostic).

*Follow-up:* Nothing to change first (H12 has landed); if it recurs, the fix is the one the rationale names — scan for `NimbleCSV.define` and rewrite bare `NimbleCSV.parse_string/2` to the defined parser module

*Appendix A:* not covered

#### row 112 — **DROP**  ·  `Credence.Semantic.NoBareReturnInUnless (live)`

The report is factually wrong. It claims the fix "corrupts" `@type fill_mode :: :nil | :forward` by rewriting `:nil` to `nil` — but in Elixir `nil` IS the atom `:nil` (`nil == :nil` → `true`, verified), so the rewrite is a no-op semantically. My probe confirms the current rule emits `@type fill_mode :: nil | :forward` and otherwise restructures the early exit correctly.

*Appendix A:* not covered

#### row 115 — **FIX-CREDENCE**  ·  `Credence.Semantic.FixLocalFunctionInGuard (live, credence/lib/semantic/fix_local_function_in_guard.ex)`

REPRODUCED LIVE: on `defp is_blank(l), do: byte_size(String.trim(l)) == 0` + `def f(line) when is_blank(line)`, `Credence.Semantic.fix_with_trace/2` returns `applied=[]` — nothing matches `cannot find or invoke local is_blank/1 inside a guard`, and the log confirms `no rule matched diagnostic` 4×. The rule's matcher misses the message shape when the local function is actually defined in the module.

*Follow-up:* Fix alongside rows 145, 192 and 196 — four rows, one file, four distinct message shapes it fails to cover

*Appendix A:* not covered

#### row 119 — **DROP**  ·  `Credence.Semantic.NoHallucinatedBaseHexEncode (credence_evolution only)`

1 AR line truncated; the rule never fired because it only matches `Base.hex_encode/1,2`, not `Base.hex_encode64/1`. docs/18 already dispositions it `salvage-small-fix`, `dup_of Credence.Semantic.UndefinedFunction (detection only; its fix is a verified no-op on this diagnostic)`.

*Follow-up:* Add `hex_encode64`/`hex_encode32` to that salvage item's scope

*Appendix A:* not covered

#### row 122 — **DROP**  ·  `Credence.Semantic.UndefinedFunction (live)`

Already fixed. The report is that `Map.has?/2 is undefined or private` went unmatched across three attempts; on credence HEAD `Credence.Semantic.fix_with_trace/2` returns `applied=[{Credence.Semantic.NoMapHas, 1}]` and rewrites it to `Map.has_key?/2`.

*Appendix A:* not covered — and Appendix A's shorthand "rules that exist in-repo (UndefinedFunction…)" is misleading here: UndefinedFunction exists but did not fire on this row, so the closed-set rejection was correct

#### row 125 — **RE-QUEUE**  ·  `Credence.Pattern.NoRedundantAssignment (live)`

Log shows `NoRedundantAssignment: check found ... fix returned IDENTICAL source`, so it is a genuine detect-without-fix that lib/pattern.ex:158 hides from the closed set. My repro (`dp = Enum.reduce(...); dp`) is fixed correctly by the current rule, so the surviving gap is the `unless`-guarded accumulator shape the rationale describes.

*Follow-up:* FIX-CREDENCE lib/pattern.ex:158 first so the next run can name it

*Appendix A:* not covered — Appendix A cites NoRedundantAssignment as a "rule that exists", implying a lookup bug; the real reason it is absent is the no-op-fix exclusion

#### row 129 — **DROP**  ·  `fix_underscored_fn_param_binding_for_body_use (deleted in 4.6c)`

Under-fire on `_tv` in a head then `tv` in the body — the rule never fired, so it was never in the closed set. Deleted in 4.6c as `delete-implementation-dead`. The re-ask also drifted to a second non-existent name, `FixUndefinedUnderscoredBinding`.

*Appendix A:* not covered

#### row 134 — **DROP**  ·  `prefer_double_quoted_atom (deleted in 4.6c)`

Under-fire on `:'$end_of_table'`; 1 AR line truncated. Deleted in 4.6c as `delete-implementation-dead`.

*Appendix A:* not covered

#### row 136 — **DROP**  ·  `fix_nested_module_short_reference (deleted in 4.6c)`

Under-fire on `Shard.get/2` inside `LRUCacheSharded`; deleted in 4.6c as `delete-implementation-dead`. The re-ask also collapsed to `:missing_decision`, so the row burned both attempts.

*Appendix A:* not covered

#### row 138 — **RE-QUEUE**  ·  `Credence.Pattern.NoRedundantAssignment (live)`

Same detect-without-fix as row 125 (`tid = :ets.new(...); tid` inside a case-clause body, `check found` then `IDENTICAL source`), invisible to the closed set via lib/pattern.ex:158.

*Follow-up:* FIX-CREDENCE lib/pattern.ex:158

*Appendix A:* not covered

#### row 139 — **RE-QUEUE**  ·  `Credence.Pattern.NonGroupedClauses (live)`

The sharpest evidence in the cluster for the no-op exclusion: all three attempts log `NonGroupedClauses: check found 1 issue(s), running fix...` immediately followed by `APPLIED_RULES: [{Credence.Semantic.UnusedVariable, 1}]` — the rule fired and is absent. My repro (two `handle_call/3` split by a `defp`) is now fixed correctly, so the surviving gap is the 5-clause / 2-helper shape.

*Follow-up:* FIX-CREDENCE lib/pattern.ex:158, then re-queue

*Appendix A:* not covered — Appendix A lists NonGroupedClauses under "rules that exist in-repo", but existence was never the problem

#### row 141 — **RE-QUEUE**  ·  `Credence.Pattern.NonGroupedClauses (live)`

Same `check found` → `IDENTICAL source` exclusion as row 139. The re-ask also failed differently — the model switched to a POTENTIAL_NEW_RULE (`no_default_arg_shadows_same_arity_clause`) and omitted PHASE, giving `{:bad_phase, nil}`.

*Follow-up:* FIX-HARNESS — the re-ask appends only the error reason, not a restatement of the required blocks, so a decision switch loses mandatory fields

*Appendix A:* not covered

#### row 145 — **FIX-CREDENCE**  ·  `Credence.Semantic.FixLocalFunctionInGuard (live)`

REPRODUCED LIVE: `def f(x) when table() == :ok` yields `applied=[]` — nothing matches `cannot find or invoke local table/0 inside a guard`, matching the log's `no rule matched diagnostic`. This is also the one row where the `APPLIED_RULES` line itself was cut mid-list (`…{Credence.Pattern.NoCondTwoClauses, (truncated)`), which `Cev.AppliedRules.@line` silently discards because its regex requires a closing `]`.

*Follow-up:* FIX-HARNESS — make `AppliedRules.@line` tolerate a truncated list body (parse pairs even without the closing bracket); fix the rule with rows 115/192/196

*Appendix A:* not covered

#### row 150 — **DROP**  ·  `no_after_or_rescue_in_case (deleted in 4.6c)`

Under-fire report (`catch` inside `case` not covered); 1 AR line truncated. Deleted in 4.6c as `delete-duplicate` of `Credence.Semantic.FixAfterOrRescueInCase`.

*Follow-up:* Check whether the surviving FixAfterOrRescueInCase covers `catch` — rows 49 and 150 both asked for it

*Appendix A:* not covered

#### row 156 — **DROP**  ·  `fix_pin_on_non_variable (deleted in 4.6c)`

Under-fire on `^self()` — the log shows `no rule matched diagnostic` 6×. Deleted in 4.6c as `delete-implementation-dead`.

*Appendix A:* not covered

#### row 164 — **FIX-CREDENCE**  ·  `Credence.Syntax.NoFnAsVariable (live, credence/lib/syntax/no_fn_as_variable.ex)`

REPRODUCED LIVE: on `defp try_fns([fn | rest], v), do: fn.(v) || try_fns(rest, v)` — genuinely unparseable source — `Credence.Syntax.analyze/2` returns 0 issues and `fix_with_trace/2` returns `applied=[]` with the source still not parsing. The rule only handles expression-position `fn`-as-variable, not pattern position (function heads, case clauses).

*Follow-up:* Extend the matcher to pattern position; a Syntax under-fire leaves no trace at all (Syntax rules have no `check`), so it can never be surfaced through the BUGFIX lane

*Appendix A:* not covered

#### row 171 — **DROP**  ·  `fix_underscored_fn_param_binding_for_body_use (deleted in 4.6c)`

Under-fire when the un-underscored reference is in a guard rather than the body. Deleted in 4.6c as `delete-implementation-dead`.

*Appendix A:* not covered

#### row 175 — **DROP**  ·  `fix_struct_update_on_dynamic_variable (deleted in 4.6c)`

The rule matched the diagnostic and changed the source, but 1 AR line was truncated. Deleted in 4.6c as `delete-implementation-dead`, `dup_of Credence.Semantic.NoStructUpdateOnUntypedVariable`.

*Appendix A:* not covered

#### row 176 — **DROP**  ·  `fix_underscored_pattern_binding_for_body_use (deleted in 4.6c)`

Under-fire on `%Step{name: _name}` + bare `name` in the body; the rule never fired. Deleted in 4.6c as `delete-implementation-dead`.

*Appendix A:* not covered

#### row 179 — **DROP**  ·  `no_import_local_function_conflict (deleted in 4.6c)`

The rule matched and rewrote `struct/2` call sites incompletely (2 of 3 AR lines truncated). Deleted in 4.6c as `delete-implementation-dead` with only partial duplicates noted.

*Appendix A:* not covered

#### row 181 — **DROP**  ·  `Credence.Semantic.FixCyclicStructReference (live)`

The report is a diff-rendering artefact, not a rule bug. `RuleHelpers.log_diff/3` pairs lines POSITIONALLY, so a correct module reorder prints as total annihilation (`L1 - defmodule Factory` / `L1 + defmodule MyApp.User`) — the classifier read that as "replaced ~16k chars of Factory logic with schema stubs". `MyApp.User/Post/Repo` were already in the source and the fix moved `Factory` to L42, exactly the documented reorder; the follow-on compile error (`unknown fields [:__meta__] in :except`) is in the LLM's own code.

*Follow-up:* FIX-CREDENCE `RuleHelpers.log_diff/3` (credence/lib/rule_helpers.ex:938) — emit a real diff and bound its size; this renderer is both the source of fabricated bug reports and the thing that blows the 8096-byte log budget

*Appendix A:* not covered

#### row 183 — **FIX-CREDENCE**  ·  `Credence.Semantic.NoHallucinatedDefpstruct (live) + Credence.Semantic.UndefinedFunction (live)`

REPRODUCED LIVE: on `defpstructp now: 0`, `NoHallucinatedDefpstruct` does not match, and `UndefinedFunction` claims the diagnostic and no-ops (`applied=[{Credence.Semantic.UndefinedFunction, 1}] changed=false`). Because Semantic records a no-op as applied, the diagnostic is consumed and no other rule gets a chance.

*Follow-up:* Widen NoHallucinatedDefpstruct to the `defpstructp` variant, and make UndefinedFunction decline diagnostics it cannot rewrite rather than swallowing them

*Appendix A:* not covered

#### row 192 — **FIX-CREDENCE**  ·  `Credence.Semantic.FixLocalFunctionInGuard (live)`

Third message shape the rule misses: `cannot find or invoke local __match_pattern__/2 inside a guard`, logged as `no rule matched diagnostic` across attempts. The rationale's guess — the matcher does not cover the message's `Called as: …` suffix — is worth checking first.

*Follow-up:* Fix with rows 115/145/196

*Appendix A:* not covered

#### row 196 — **FIX-CREDENCE**  ·  `Credence.Semantic.FixLocalFunctionInGuard (live) / NoHallucinatedGuardFn (live)`

REPRODUCED LIVE and it is worse than the row reports: on `def f(r) when is_range(r)`, `FixLocalFunctionInGuard` DOES match and returns identical source (`applied=[{Credence.Semantic.FixLocalFunctionInGuard, 1}] changed=false`). It therefore consumes the diagnostic that `NoHallucinatedGuardFn` should have handled, so widening NoHallucinatedGuardFn alone would not help.

*Follow-up:* Make FixLocalFunctionInGuard decline (return `:no_match`) when it cannot rewrite, so the diagnostic falls through; this pairs with the general 'claim-then-no-op' problem in lib/semantic.ex:152

*Appendix A:* not covered

#### row 203 — **RE-QUEUE**  ·  `Credence.Pattern.NoRedundantAssignment (live)`

Third instance of the detect-without-fix exclusion (`check found` 3× per attempt, `IDENTICAL source` each time). All AR lines were present here, which proves the absence is the no-op exclusion in lib/pattern.ex:158 and not truncation.

*Follow-up:* FIX-CREDENCE lib/pattern.ex:158

*Appendix A:* not covered

#### row 210 — **DROP**  ·  `no_import_local_function_conflict (deleted in 4.6c)`

All three AR lines lost to truncation → empty closed set. The real culprit is `NoImportLocalFunctionConflict`, which renamed the public `def apply/3` to `generate_apply/3` (log line 3697); the model's second attempt misattributed it to `NoDuplicateDefstruct`, which fired for an unrelated defstruct merge. The culprit was deleted in 4.6c as `delete-implementation-dead`.

*Follow-up:* FIX-HARNESS name normalisation (`semantic/no_import_local_function_conflict` was the emitted form)

*Appendix A:* not covered

#### row 211 — **FIX-HARNESS**  ·  `- (POTENTIAL_NEW_RULE `syntax/no_elsif`)`

Both attempts died on output-shape gates, not on content: attempt 1 gave `PROPOSED_NAME=syntax/no_elsif`, rejected by `@snake` as `{:bad_proposed_name}`; attempt 2 re-labelled the same `elsif` proposal `phase: semantic`, so `require_before/1` applied the parse gate to a deliberately unparseable `before` → `{:does_not_parse, :before}`. Both are the prompt teaching `<phase>/<name>` while the gates demand bare snake_case and a phase-consistent `before`.

*Follow-up:* Strip a leading `<phase>/` from PROPOSED_NAME before the snake check, and re-ask with the phase taxonomy restated when `before` fails to parse under a non-syntax phase; the proposal itself is a duplicate of the live `Credence.Syntax.FixElsifInIfChain` (repaired in fe6c2f7)

*Appendix A:* yes on the count (1 `does_not_parse`); the mechanism is not covered

#### row 213 — **DROP**  ·  `Credence.Semantic.NoBareReturnInUnless (live)`

Already fixed. The report is that the rule "strips `return` … leaving dead code that falls through to the wrong value" — that is precisely what commit 86ee66b (`make NoBareReturnInUnless restructure early exits instead of deleting them`) repaired during Phase 4. My probe confirms the current rule restructures into `if/else` rather than deleting.

*Appendix A:* not covered

#### row 224 — **DROP**  ·  `no_define_to_string (deleted in 4.6c)`

All three AR lines lost to truncation → empty closed set; the model answered with `no_define_to_string` / `semantic/no_define_to_string`. The over-fire it reports (renaming a public `def to_string/1` to `key_to_string`) is real but the rule was deleted in 4.6c as `delete-implementation-dead`.

*Follow-up:* FIX-HARNESS name normalisation

*Appendix A:* not covered

#### row 227 — **RE-QUEUE**  ·  `Credence.Pattern.NoRedundantAssignment (live)`

Fourth instance of the same exclusion; all AR lines present, `NoRedundantAssignment: check found` then `IDENTICAL source`. My repro of the plain `dp = expr; dp` shape is fixed correctly today (`applied=[{NoReduceForMapBuilding,1},{NoRedundantAssignment,1}]`), so the residual gap is the shadowed-rebinding shape the rationale describes.

*Follow-up:* FIX-CREDENCE lib/pattern.ex:158

*Appendix A:* not covered

#### row 228 — **RE-QUEUE**  ·  `Credence.Semantic.UndefinedFunction (live)`

Confirmed still unhandled — `:crypto.exactly_equal?/2` yields `applied=[]` on credence HEAD, and the log shows `no rule matched diagnostic` 8×. But this is a MISSING rule, not a defect in UndefinedFunction: there is no deterministic rewrite for an invented `:crypto` function, so the correct lane is POTENTIAL_NEW_RULE, which the prompt's `## Rules that already fired` framing steered the model away from.

*Follow-up:* FIX-HARNESS — the prompt must stop implying every unmatched diagnostic is an existing rule's fault (see NO_ACTION class 2)

*Appendix A:* not covered

### switch_proposals

#### row 2 — **DROP**  ·  `fix_process_send_after_infinity (proposed) / no_process_send_after_infinity (incumbent, credence_evolution only)`

The Phase 4.4 decline holds, and I can now confirm it by execution rather than by survey. The proposal declares PHASE=semantic; I ran its own `===BEFORE===` block through live credence and `Credence.RuleHelpers.compile_and_capture/1` returns `{:ok, []}` — zero diagnostics — so `Credence.Semantic.analyze/2` returns `[]` and `fix_with_trace/2` applies nothing (`Semantic applied: []`); `Pattern.analyze` and `Syntax.analyze` also return `[]`. A semantic rule keys on a compiler diagnostic, so the proposed rule is unreachable in its own declared phase on its own headline example, and a switch gating an unreachable rule buys nothing. Two things the decline did NOT have, both of which strengthen it: (1) the proposal's RATIONALE — 'the existing `no_process_send_after_infinity` rule detected this exact crash on every attempt but returned IDENTICAL source — its fix is broken' — is FALSE on both halves. The run is timestamped 2026-07-07 21:46 (ts=1783453578); at that commit (credence_evolution 5fac292, 2026-07-07 11:00) the rule's `@match_msg` was the literal string `"redefining module"` (it only became 'has multiple clauses and also declares default values' at 47452e5, 2026-07-13 18:47). So 'matched diagnostic' means it matched a phantom `redefining module …` warning, not the `:infinity` crash — which emits no diagnostic at all. And 'IDENTICAL source' is correct behaviour, not a broken fix: at 5fac292 `collect_patches/2` only handled a LITERAL `:infinity` third argument, while all three attempts pass a variable (`cleanup_interval`, then `cleanup_delay`), so `patches == []` → `source`. Proof the phantom diagnostic is real and is what the rule saw: committed/37.log:1274 records `credence check` failing exit=1 with the issue text `no_process_send_after_infinity: redefining module OneTimeTokenStore (current version loaded from _build/test/lib/workspace/ebin/Elixir.OneTimeTokenStore.beam) (line 1)`. (2) The proposal's declared `divergence_class` is understated. It says only 'the timer is not scheduled, so no :cleanup message will arrive'. It omits that the AFTER binds `ref = :infinity` — an atom in a field that held a timer reference — so any downstream `Process.cancel_timer(ref)`/`Process.read_timer(ref)` raises ArgumentError 'not a reference' (verified). Conversely, on every input where BEFORE does not crash (`cleanup_interval` an integer) the `if` takes the else branch and AFTER is byte-equivalent, so the rewrite is a REPAIR, not an assumption-gated divergence — the switch is unnecessary even on its own terms. Relocating the rule to the pattern phase (where the BEFORE does compile, so it is reachable) does not rescue it either: the AFTER wraps EVERY `Process.send_after` whose delay is non-literal, which is precisely the over-firing criterion docs/18 §128 forbids porting ('do NOT rebuild this rule's actual criterion of any non-literal third argument, which flags every idiomatic Process.send_after(self(), :tick, interval) call', 'do NOT port its auto-fix'). Faithful contents of 2.json for the record: name `fix_process_send_after_infinity`, default `true`, phase `semantic`, decision `SWITCH_PROPOSAL`, emitted by xiaomi_mimo_2_5_pro on the FAILED-solve lens of task 001_003_hierarchical_limiter_01. Nothing in the row is a rule worth building here; the failure mode itself remains alive as docs/18's report-only pattern rebuild item #5. Keep 2.log until the harness item below lands — it is the primary evidence for it — then delete both files.

*Follow-up:* FIX-HARNESS: `Credence.RuleHelpers.compile_and_capture/1` (/home/kamil/projects/credence/lib/rule_helpers.ex:160-186) calls `Code.compile_string/2` without `ignore_module_conflict`, so if the target module is already loaded in the BEAM the compiler emits a phantom `severity: :warning, position: 1, message: "redefining module X (current version loaded from …beam)"` that describes the host VM, not the source. Reproduced: preload the module from a binary, then `compile_and_capture/1` on the identical source returns that warning (clean VM returns `{:ok, []}`). The harness makes this the NORMAL case — `Cev.Validator.run_credence_fix/1` (/home/kamil/projects/credence-evolution-harness/lib/cev/validator.ex:320-333) shells `mix run --no-compile run_credence_fix.exs` inside the warm, already-compiled `var/run/workspace`, and the `credence check` step does the same. Costs observed: the phantom warning is fed to every semantic rule's `match?/1` (it is what let a rule whose `@match_msg` was the string 'redefining module' fire on unrelated code), it made `credence check` return a bogus ISSUE and exit 1 on committed/37 — corrupting that row's validator verdict — and it manufactured the false premise that produced this very switch proposal. 'redefining module' appears across at least 10 logs in var/run/logs (escalated/2, escalated/20, committed/8, committed/15, committed/37, classifier_errors/23, 38, 139, 181, 228). Fix on the harness side by invoking credence against a cold module table (or unloading the solution module before the fix/check script runs); harden on the credence side by setting `ignore_module_conflict: true` around the `Code.compile_string` in `compile_and_capture/1`, or by purging/deleting the target module before compiling as well as after. Second followup: correct docs/16 §4.4 and the Appendix A table row, which both repeat the proposal's false claim that the incumbent rule's 'no-op fix is confirmed broken'.

*Appendix A:* Partly. Appendix A's Switch-proposal row and docs/16 §4.4 reach the same disposition I do (decline / decide it in the 4.4 batch; a switch over an unreachable rule buys nothing), and §4.4's reachability argument is correct — I confirmed it by execution. But Appendix A's stated ground, 'the underlying rule's no-op fix is confirmed broken' (echoed at docs/16:396 as 'confirmed broken (returns identical source — flagged independently by escalated/20, a classifier-error rationale, and the switch proposal)'), is wrong: at the commit in force during this run the fix was correctly scoped to a literal `:infinity` and returned the source unchanged because the input passes a variable. What is broken is the rule's `match?/1` (`@match_msg "redefining module"`, a fabricated key) plus the harness-manufactured diagnostic it keys on. Appendix A also does not mention the two findings above (the incomplete divergence_class, and that the rewrite is a repair rather than an assumption).

---

## Re-queue list for the next run

26 rows, each with what must change first:

| row | rule | blocked on |
|---|---|---|
| 1 | `no_hallucinated_map_empty (proposed; semantic)` | Blocked on the equivalence-battery fix (see cluster findings); dedupe against row 18, which proposes the identical target and fix under the name `no_map_empty`. Home is a sibling of lib/semantic/no_map_has.ex, or a new UndefinedFunction replacement type (the e |
| 1 | `Credence.Pattern.RemoveUnreachableClausesAfterCatchall (live, credence/lib/pattern/)` | FIX-CREDENCE lib/pattern.ex:158 — record `{rule, :no_op}` in the trace instead of silently dropping it (this is docs/16 C5); nothing else needs to change before re-queue |
| 6 | `proposed Credence.Semantic.FixRecursiveVariableInPattern` | FIX-HARNESS — the Router should treat an implementer session that wrote no files as a null run (retry / distinct outcome), not as `:cc_tests_red`. Also LD1 evidence in this same log: `[Classify] re-ask after invalid spec: {:rule_name_not_in_closed_set, Credenc |
| 7 | `no_hallucinated_float_coerce (proposed; semantic)` | Blocked on the battery fix. Cheapest of the 13 to land: a one-line entry `{"Float", "coerce", 1} => {:rename, ":erlang", "float"}` in @qualified_replacements, lib/semantic/undefined_function.ex. |
| 7 | `Credence.Semantic.NoRescueInException (live)` | Nothing to change first — H12 (commit 60ce2c4) already routes the closed set through the untruncated sidecar |
| 18 | `no_map_empty (proposed; semantic)` | Blocked on the battery fix; merge with row 1 before re-queueing so the next run does not build the rule twice under two names. |
| 23 | `Credence.Pattern.RemoveUnreachableClausesAfterCatchall (live)` | FIX-CREDENCE lib/pattern.ex:158 (record no-op fixes); re-queue afterwards |
| 59 | `Credence.Pattern.NoRedundantAssignment (live)` | FIX-HARNESS name normalisation; re-queue once H12's sidecar is exercised |
| 99 | `Credence.Semantic.FixNimbleCsvDirectParse (live)` | Nothing to change first (H12 has landed); if it recurs, the fix is the one the rationale names — scan for `NimbleCSV.define` and rewrite bare `NimbleCSV.parse_string/2` to the defined parser module |
| 100 | `proposed new syntax rule fix_unclosed_function_call_paren (blocked by Credence.Syntax.NoKeywordIfBareInTuple)` | FIX-HARNESS (shared with 119): `lib/cev/implement.ex:66` reports `String.slice(failures, 0, 400)` — the HEAD of mix output, i.e. compile warnings — while the LLM path already uses `trim/1` (last 3000 chars). Report the tail plus the ExUnit failure block, and r |
| 106 | `no_datetime_accessor_as_function (proposed; semantic)` | Blocked on the battery fix. Home is the existing hallucinated-accessor family — lib/semantic/fix_hallucinated_naive_datetime_accessor.ex and lib/semantic/fix_hallucinated_calendar_iso_accessor.ex share one Sourceror anchored-rewrite skeleton (match on the exac |
| 107 | `no_hallucinated_date_to_tuple (proposed; semantic)` | Blocked on the battery fix. Prefer the stdlib target over the classifier's field triple: `Date.to_erl/1` exists and returns exactly {year, month, day}, so this collapses to a one-line entry `{"Date", "to_tuple", 1} => {:rename, "Date", "to_erl"}` in lib/semant |
| 119 | `proposed new semantic rule fix_logical_or_in_guard` | FIX-HARNESS first (same defect as row 100): report the failure tail, the exit code, and which `mix test` leg failed, so a repeat is diagnosable. Note for the future rule: the diagnostic arrives with `position: 0` (no line), so it must not key on a line number. |
| 125 | `Credence.Pattern.NoRedundantAssignment (live)` | FIX-CREDENCE lib/pattern.ex:158 first so the next run can name it |
| 138 | `Credence.Pattern.NoRedundantAssignment (live)` | FIX-CREDENCE lib/pattern.ex:158 |
| 139 | `Credence.Pattern.NonGroupedClauses (live)` | FIX-CREDENCE lib/pattern.ex:158, then re-queue |
| 141 | `Credence.Pattern.NonGroupedClauses (live)` | FIX-HARNESS — the re-ask appends only the error reason, not a restatement of the required blocks, so a decision switch loses mandatory fields |
| 144 | `fix_reduce_with_halt (proposed; does not exist in credence or the sister)` | Nothing has to change in the harness first. Add to the re-queue prompt: this is a REPAIR (before crashes on every halting input that isn't the last element; when halt fires on the last element `reduce` silently returns `{:halt, acc}`), so the equivalence test  |
| 162 | `fix_hallucinated_task_stop (proposed; semantic)` | Blocked on the battery fix. One-line entry `{"Task", "stop", 2} => {:rename, "Task", "shutdown"}` in lib/semantic/undefined_function.ex; distinct from the shipped Credence.Pattern.FixTaskShutdownBrutalKill, which fixes the :brutal atom, not the function name.  |
| 164 | `no_hallucinated_task_pid_fn (proposed; semantic)` | Blocked on the battery fix. This is the lowest-risk of the thirteen: lib/semantic/fix_task_ref_field_access.ex and lib/semantic/fix_task_id_field_access.ex are already shipped for the sibling fields, so it is the same rule with ref -> pid, including the existi |
| 169 | `fix_missing_paren_after_fn_end (proposed; gap still open in credence)` | FIX-HARNESS: the log records `agent done — subtype=success turns=23` and the Router files `gave_up: {:cc_tests_red, …}`, so a provider-side refusal is being booked as a substantive test failure. H9's environmental-failure triage must key on the refusal string  |
| 203 | `Credence.Pattern.NoRedundantAssignment (live)` | FIX-CREDENCE lib/pattern.ex:158 |
| 205 | `fix_hallucinated_make_tuple_arity (proposed; semantic)` | Blocked on the battery fix. While re-queueing, note a second uncovered target in the same row's later attempts: `undefined function setelement/3` (an Erlang BIF that is not auto-imported in Elixir), also listed unfixed and also absent from undefined_function.e |
| 225 | `prefer_pattern_match_for_struct_field_validation (proposed)` | FIX-CREDENCE first, then re-queue: `test/support/behaviour_equivalence.ex:312` — rename all references to the module, not just the `defmodule` header (word-boundary global replace, or inject `alias Eqv_Before_N, as: Money`), and add a positive control that a s |
| 227 | `Credence.Pattern.NoRedundantAssignment (live)` | FIX-CREDENCE lib/pattern.ex:158 |
| 228 | `Credence.Semantic.UndefinedFunction (live)` | FIX-HARNESS — the prompt must stop implying every unmatched diagnostic is an existing rule's fault (see NO_ACTION class 2) |

