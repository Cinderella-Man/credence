## ordering — 2026-08-24T21:07:50+02:00

FINDINGS

- blocker: lib/semantic/no_hallucinated_guard_fn.ex:44 — claims every `is_regex/1` guard diagnostic without verifying the function is actually hallucinated; with `defp is_regex(x), do: Regex.match?(~r/a/, x)` and `def f(x) when is_regex(x)`, `FixLocalFunctionInGuard` correctly declines, then semantic fall-through hands ownership here and rewrites the intended string predicate to `is_struct(x, Regex)`, silently changing behavior.

## interaction — 2026-08-24T21:09:08+02:00

FINDINGS

- blocker: lib/semantic.ex:460 — diagnostics are captured once and then fixed right-to-left under the assumption that each repair only affects text to its right, but `FixPlugDependencyModuleOrder` can move entire modules; when a later-line missing `Dependency.init/1` diagnostic reorders modules before an earlier `List.max/1` diagnostic is processed, the latter retains its old line number and `UndefinedFunction` may rewrite the wrong line or decline, making one rule’s repair change another rule’s admission and output.

## masking — 2026-08-24T21:09:55+02:00

FINDINGS

- blocker: lib/source_mask.ex:343 — paired sigil delimiters can nest, but the scanner terminates at the first closing delimiter; `~s(prefix (inner) 100% done)` exposes `100% done)` as code, allowing rules such as `FixPythonModulo` to rewrite bytes inside the sigil when the file is otherwise malformed.

## convergence — 2026-08-24T21:10:48+02:00

FINDINGS

- concern: test/support/idempotency.ex:123 — any exception or throw during either repair pass is converted to `false`, so the idempotency gate reports a fixpoint and permits a new ledger-free offender when pass 1 or the repaired pass crashes; triggering input is any fixture whose first repair exposes a shape that makes a later `Credence.fix/1` invocation raise or throw.

## containment — 2026-08-24T21:11:44+02:00

FINDINGS
- blocker: lib/rule_helpers.ex:276 — compilation remains in-process, so arbitrary analyzed source containing `System.halt(0)` terminates the entire Credence VM despite the child-process timeout and heap limit.
- blocker: lib/rule_helpers.ex:270 — the heap and timeout bounds apply only to the compiler child; source such as `spawn(fn -> Stream.repeatedly(fn -> :binary.copy(<<0>>, 1_000_000) end) |> Enum.to_list() end)` compiles successfully and leaves an unbounded orphan consuming memory after the monitored child exits.
- blocker: test/support/behaviour_equivalence.ex:389 — module fixtures are evaluated directly with no timeout or heap ceiling; a fixture with top-level `receive do after :infinity -> :ok end` hangs the suite indefinitely, while allocating or process-spawning fixtures can exhaust the runner.
- blocker: test/support/rule_case.ex:167 — `call_fixed/4` directly compiles and executes repaired fixture text without containment; a triggering repair that emits an infinite top-level expression or a non-returning target function bypasses `compile_and_capture/1` and can hang or OOM the whole test VM.
- concern: maintainer_tools/pr_review/run_capped.sh:24 — when user systemd scopes are unavailable, the advertised safety wrapper deliberately executes the command uncapped; any documented `mix run` fixture reproduction on a container, CI shell, or host without a user systemd session regains the machine-level OOM failure this wrapper claims to prevent.

## tests — 2026-08-24T21:12:23+02:00

FINDINGS

- nit: test/alpha_rename_test.exs:84 — substring-only assertion can pass if renaming also corrupts surrounding module code; triggering input is the existing `@re` fixture whose output merely needs to retain `@re =~ v1`.
- nit: test/alpha_rename_test.exs:90 — two independent substring assertions can pass with duplicated, reordered, or otherwise malformed output; triggering input is the existing `get_items?/1` fixture if the output contains both fragments anywhere.

## performance — 2026-08-24T21:13:25+02:00

FINDINGS

- concern: test/corpus/fix_safety_test.exs:23 — this full-corpus sweep is `async: true` while `over_firing_test.exs` and `scope_parity_test.exs` are also async and each launches `System.schedulers_online()` workers; `mix test --only corpus` therefore runs roughly three scheduler-wide, parse-heavy sweeps concurrently, oversubscribing CPU and multiplying live AST/source memory on high-core CI runners.
- concern: test/test_helper.exs:34 — enabling the idempotency sweep by default adds roughly 9–10 minutes to every unqualified local `mix test`, including workflows that do not pass the newly documented exclusion; the triggering input is any standard `mix test` invocation, which now processes about 5,200 fixtures through the complete repair pipeline twice.

## operational resolution — 2026-08-24

- The `run_capped.sh:24` concern is resolved in review tooling commit `e37d6989`'s successor: when user systemd scopes are unavailable, the wrapper uses `prlimit` to impose an inherited address-space ceiling instead of silently running uncapped.
