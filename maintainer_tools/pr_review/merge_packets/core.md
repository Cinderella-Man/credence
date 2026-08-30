# Architecture and shared core

Candidate: `8cb5afd3` against `main`.

## Files

- `lib/credence.ex` — pending, verdict: not reviewed
- `lib/credence/corpus.ex` — pending, verdict: not reviewed
- `lib/credence/corpus/analysis_cache.ex` — pending, verdict: not reviewed
- `lib/credence/corpus/budget.ex` — pending, verdict: not reviewed
- `lib/credence/corpus/findings.ex` — pending, verdict: not reviewed
- `lib/credence/mutation.ex` — pending, verdict: not reviewed
- `lib/credence/mutation/sweep.ex` — pending, verdict: not reviewed
- `lib/dsl_guard.ex` — pending, verdict: not reviewed
- `lib/mix/tasks/credence.corpus.ex` — pending, verdict: not reviewed
- `lib/mix/tasks/credence.covers.ex` — pending, verdict: not reviewed
- `lib/mix/tasks/credence.equiv.ex` — pending, verdict: not reviewed
- `lib/mix/tasks/credence.fires.ex` — pending, verdict: not reviewed
- `lib/mix/tasks/credence.fix_tests.ex` — pending, verdict: not reviewed
- `lib/mix/tasks/credence.mutants.ex` — pending, verdict: not reviewed
- `lib/pattern.ex` — pending, verdict: not reviewed
- `lib/rule_helpers.ex` — pending, verdict: not reviewed
- `lib/rule_scaffold.ex` — pending, verdict: not reviewed
- `lib/semantic.ex` — pending, verdict: not reviewed
- `lib/source_mask.ex` — pending, verdict: not reviewed
- `lib/syntax.ex` — pending, verdict: not reviewed

## Active findings

- **blocker** `lib/semantic.ex` — lib/semantic.ex:460 — diagnostics are captured once and then fixed right-to-left under the assumption that each repair only affects text to its right, but `FixPlugDependencyModuleOrder` can move entire modules; when a later-line missing `Dependency.init/1` diagnostic reorders modules before an earlier `List.max/1` diagnostic is processed, the latter retains its old line number and `UndefinedFunction` may rewrite the wrong line or decline, making one rule’s repair change another rule’s admission and output.
- **blocker** `lib/source_mask.ex` — lib/source_mask.ex:343 — paired sigil delimiters can nest, but the scanner terminates at the first closing delimiter; `~s(prefix (inner) 100% done)` exposes `100% done)` as code, allowing rules such as `FixPythonModulo` to rewrite bytes inside the sigil when the file is otherwise malformed.
- **blocker** `lib/rule_helpers.ex` — lib/rule_helpers.ex:276 — compilation remains in-process, so arbitrary analyzed source containing `System.halt(0)` terminates the entire Credence VM despite the child-process timeout and heap limit.
- **blocker** `lib/rule_helpers.ex` — lib/rule_helpers.ex:270 — the heap and timeout bounds apply only to the compiler child; source such as `spawn(fn -> Stream.repeatedly(fn -> :binary.copy(<<0>>, 1_000_000) end) |> Enum.to_list() end)` compiles successfully and leaves an unbounded orphan consuming memory after the monitored child exits.


## Maintainer decision

- [ ] Accept
- [ ] Needs changes
- [ ] Blocked on a documented human decision
