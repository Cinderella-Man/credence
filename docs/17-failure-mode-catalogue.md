# The Credence failure-mode catalogue

*Distilled from 140 rejected Credence rules. Verified on Elixir 1.20.2 / Erlang OTP 29.*

The rules were rejected as code. Each still encodes an observation about how LLM-generated Elixir fails, and every observation below was re-checked by executing it — parse, compile, run — not by reading the rule's docstring. Docstrings turned out to be the least reliable artefact in the set.

> **Status 2026-07-27.** The deletion this document was written to authorise has happened: 112 modules and 227 tests were removed from `credence_evolution` in commit `b83d623`, which is pushed to `origin/evolution` and therefore recoverable. 27 rules were **kept** (17 rebuild-later, 9 salvage, 1 already-live) — see `docs/18-per-rule-verdicts.json` for which. Four of the delete verdicts turned out not to be standalone rules at all but deltas of files that exist on `main`, and were restored rather than deleted.
>
> **Read `docs/18` §5.3 before using the "What is worth building" list at the end of this file.** That list took heavy damage on adversarial review and has *not* been rewritten: item 2's two headline grounds were both falsified (corpus precision 0/1 in 28,303 files), item 6 found 0 true positives on the maintainer's own corpus, item 7's supervisor-restart story is false, and items 3, 5 and 11 prescribe a deliverable the Pattern phase bans. The per-mode executed evidence in this document is sound; the *rankings* and the cluster narratives are not.

## Headline numbers

| | count |
|---|---|
| Rules examined | 140 |
| Encode a real defect | 137 |
| Encode a non-defect (premise inverted) | 3 |
| **Real failure modes nothing catches** — no compiler diagnostic, no Credo, no Dialyzer-without-PLT | **26** |
| Caught only partially (type checker fires on literals, silent on variables) | 4 |
| Compile errors (build stops) | 73 |
| Runtime crashes (build green) | 45 |
| Silent wrong answers | 9 |
| Hangs / deadlocks | 2 |
| Style / deprecation only | 9 |
| Distinct misconception clusters | 25 proposed → 22 after correction |
| Clusters put under adversarial refutation | 12 |
| **Clusters that survived refutation intact** | **0** |
| Rules whose own premise or matcher was factually wrong about Elixir | 26 |
| Rules structurally inert in the pipeline they were filed in | ≥18 |

Mechanism split: 55 semantic-diagnostic, 36 pattern/AST, 30 compiler-already-catches, 18 syntax-parse-failure, 1 not-mechanizable.
Disposition split: 54 port-the-rule, 51 catalogue-entry-only, 32 duplicate-of-another, 3 discard-premise-false. Note that `port-the-rule` was assigned before the refutation pass; several of those rules have fixes that are actively harmful (see *What is worth building*).

The 13 clusters that were never adversarially refuted are marked **untested** below. Treat their root-cause narratives as provisional: the refutation pass overturned 12 out of 12 it examined.

---

# The misconceptions

Ordered by value = (does anything catch it) × blast radius × member count.

---

### 1. Process boundaries and ownership are invisible — code assumed to run "here", as "me", with my privileges and my registered name

**Members (4, all `caught_by=nothing`):** `no_send_self_in_task`, `no_private_named_ets_readable_externally`, `no_private_fn_in_timer_mfa`, `no_hardcoded_genserver_name_in_api`. **Untested by refutation.**

**Why a generator produces it.** BEAM code is written with a single-threaded mental model: there is one current process, `self()` means "this module's server", a module's functions run inside that server, and a module's name *is* its process. Nothing about the actual execution context is visible in the source.

**Failure modes.**
- `send(self(), msg)` inside a `Task.async/start_link` closure. Verified: the task's pid is `#PID<0.117.0>`, the parent's is `#PID<0.95.0>`; the message lands in `{:messages, [done: 42]}` in the *task's* mailbox and the parent's is `{:messages, []}`. `handle_info` never fires, the state stays stale, nothing crashes or warns.
- A `defp` scheduled by name through an MFA tuple (`:timer.apply_after(ms, __MODULE__, :do_cleanup, [pid])`). The compiler's only signal is `function do_cleanup/1 is unused` — which actively *misdescribes* the defect, calling a live-but-unreachable function dead. At fire time the timer process raises `UndefinedFunctionError`; the scheduling call already returned `{:ok, ref}` to an unlinked caller, so nothing propagates. Same trap for `spawn/3`, `Task.start/3`, `apply/3`, supervisor `{M,F,A}` child specs.
- A named `:private` ETS table created in `init/1` and read by a public API function that runs in the *caller's* process: `ArgumentError`, "insufficient access rights". `:private` was read as `defp` ("not globally writable"); in ETS it means only the owner may read *or* write. `:protected` is the mode that matches the code as written.
- Public API hardcoding `__MODULE__` and a literal table name while `init/1` takes both from options. Started anonymously or under a custom name, every call exits `{:noproc, {GenServer, :call, [Module, msg, 5000]}}`, taking the caller down.

**Highest-value catch: `no_send_self_in_task`.** Completely silent, and the repair is one line — bind `parent = self()` outside the closure. Ideal for automated repair because the fix is local, total, and provably meaning-preserving.

---

### 2. The client/server reply protocol modelled as "send the answer to the caller"

**Members (4, all `caught_by=nothing`):** `no_raw_send_in_genserver_handle_call`, `no_genserver_reply_in_handle_call`, `no_genserver_reply_in_handle_cast`, `no_send_to_from_in_handle_call`. **Untested by refutation.**

**Why.** The generator knows the caller is blocked and knows its pid is in scope, so it messages the pid. It does not model that `GenServer.call/3` sits in a *selective* receive keyed on a monitor/alias reference it created, so only `{ref, reply}` — i.e. `GenServer.reply(from, r)` — completes the call. `from` looks like a pid pair, so it is either destructured for its pid or handed to `send/2`. The surrounding structure looks correct because the deferred-reply pattern (`{:noreply, state}` now, reply later) *is* genuine OTP.

**Failure modes.**
- `def handle_call(msg, {caller_pid, _}, state)` + `spawn(fn -> send(caller_pid, result) end)` + `{:noreply, state}`. Verified: caller burns the full timeout then exits `{:timeout, {GenServer, :call, [...]}}` at 1001 ms, and the stray reply is left in the caller's mailbox where its *next* `receive` picks it up as its own.
- `GenServer.reply(pid, msg)` with a bare pid in `handle_cast`: `FunctionClauseError in :gen.reply/2`, server dies, client blocked in a bare `receive` with no `after` waits forever.
- `send(from, msg)` where `from` is the 2-tuple `{#PID<..>, [:alias | #Reference<..>]}`: `ArgumentError: 1st argument: invalid destination` — `send/2` accepts a 2-tuple only as `{registered_name, node}` with both atoms.

**Highest-value catch: `no_raw_send_in_genserver_handle_call`.** It is a hang, not a crash: nothing is logged at the point of the bug, and the stray message corrupts the caller's next receive. Verified: no compiler diagnostic, and no live Credence rule mentions `GenServer.reply` or `handle_call` at all.

---

### 3. OTP callback contracts treated as ordinary function semantics

**Members (4):** `no_agent_update_tuple_wrapper`, `no_bare_return_in_genserver_init`, `no_raise_in_handle_call`, `no_genserver_cast_with_raise`. **Untested by refutation.**

**Why.** Callbacks are written as if called by ordinary callers: return what you computed, raise to report bad input. In OTP the return value is a tagged instruction to the behaviour and an exception is a process exit the caller cannot `rescue`. Conventions differ per behaviour, so GenServer's `{:ok, state}` gets cross-applied to Agent, whose callback must return the bare state.

**Failure modes.**
- `Agent.update(pid, fn s -> {:ok, %{s | count: s.count+1}} end)`. Verified: the call returns `:ok`, and the agent's state silently becomes `{:ok, %{count: 1}}`. The damage lands on the *next* access as a `BadMapError` inside `Agent.Server` — displaced in both time and blame. Zero compile diagnostics.
- `def init(_opts), do: %{count: 0}` — zero warnings; `start_link` returns `{:error, {:bad_return_value, %{count: 0}}}` and the supervisor aborts its whole start sequence.
- `raise` in `handle_call/3` instead of `{:reply, {:error, r}, state}`: the server dies with all state; the caller sees an *exit*, not an exception, so its `rescue` will not catch it (it needs `catch :exit`), and subsequent calls exit `:noproc`. One client's bad argument becomes a whole-service failure.
- Validation-by-`raise` inside `handle_cast`: `cast` returns `:ok` unconditionally *before* the handler runs, so bad input silently becomes data loss plus a background crash.

**Highest-value catch: `no_agent_update_tuple_wrapper`** — worst diagnosability of the four; the other three fail at the point of the mistake.

---

### 4. `:infinity` assumed to be a universal timeout sentinel

**Members (4, all `caught_by=nothing`):** `no_process_send_after_infinity`, `no_process_send_after_literal_infinity`, `no_process_send_after_with_variable_infinity`, `no_validation_rejects_infinity_for_timeout`. **Untested by refutation.**

**Why.** `:infinity` *is* a valid timeout for `GenServer.call/3`, `receive ... after`, `Task.await/2`, `:timer.sleep/1` and most OTP options, so the model generalises "timeout" into one type admitting an atom sentinel. `Process.send_after/4` delegates to `:erlang.send_after/4`, which demands a `non_neg_integer`. "Never fire" is expressed by not scheduling at all.

**Failure modes.** Verified: `Process.send_after(self(), :tick, :infinity)` raises `ArgumentError` ("1st argument: not an integer" — the arg index is the erlang BIF's, which reads as wrong), with **zero compile diagnostics** for the variable form. In `init/1` this becomes `{:error, {:badarg, [{:erlang, :send_after, [:infinity, ...]}]}}` and a failed supervisor start at boot. The fourth member is the same one-type model seen from the other side: a validator `unless is_integer(t) and t > 0, do: raise ArgumentError` in the same module whose runtime path branches on `if interval != :infinity` — the one value the code was written to support is rejected at startup.

**Highest-value catch: `no_process_send_after_with_variable_infinity`** and its `Keyword.get(opts, :interval, :infinity)` twin. The literal is visible in review; the variable form is latent — every test that supplies an interval passes, and the crash only appears on the default configuration path.

---

### 5. A value's actual type/representation is not tracked — the variable's *name* stands in for its type

**Members (12):** `no_enum_sort_then_map_values`, `no_map_get_on_keyword_list_opts`, `fix_ets_new_string_name`, `fix_ets_options_bare_keypos`, `no_process_whereis_with_pid_arg`, `no_bare_atom_in_genserver_start_link`, `no_date_utc_today_with_arg`, `no_atom_position_in_list_key_functions`, `fix_unmatchable_tuple_destructure`, `no_genserver_tuple_piped_to_state_fn`, `fix_struct_update_on_dynamic_variable`, `prefer_pattern_match_for_non_empty_list`. **Untested by refutation.**

**Why.** The generator reasons about identifiers, not types: `payments` is "a map", `table` is "a name", `timers` is "a list of things with refs", so it applies whatever API reads well over that noun. Erlang BIFs badarg at runtime rather than failing to compile. Elixir 1.18+'s set-theoretic checker catches only the fraction where the type is locally inferable.

**Failure modes (selected, all verified).**
- `map |> Enum.sort_by(...) |> Map.values()` — **zero diagnostics**, `BadMapError` on every input. Every `Enum.*`/`Stream.*` returns a list; the whole class "`Map.*` applied to an `Enum.*` result" is one cheap AST check.
- `Map.get(opts, :key)` where `opts` is a keyword list — `BadMapError` **including for `[]`**, so even the default-args path crashes.
- `:ets.new("#{name}_data", [...])` — first arg must be an atom; presents as a supervisor restart loop, not as an ETS error.
- `:ets.new(:t, [:named_table, :set, :public, :keypos, 1])` — the `{:keypos, N}` tuple flattened into two bare elements. Parses, compiles, zero diagnostics, `ArgumentError` every call.
- `GenServer.start_link(__MODULE__, :ok, opts[:name] || __MODULE__)` — the type checker warns only for a *literal* atom; for the `||` form the result is `dynamic()` and there is no warning. `FunctionClauseError`, so the app fails to boot.
- `Process.whereis(self())` — `whereis/1` is `atom() -> pid()|nil` and looks up the name registry; `GenServer.whereis/1` is the one that accepts a pid.
- `List.keytake(timers, ref, :ref)` — field name passed as a 1-based tuple position.
- `{inserted_at, _} = DateTime.to_unix(...)` — scalar destructured as a 2-tuple; compiles, `MatchError` on every call, function 100% dead.
- `{:noreply, state} |> maybe_process()` — the reply tuple, not the state, reaches the helper. Corollary worth recording: if the helper is a pass-through the bug *disappears*, so the same shape is sometimes harmless.

**Highest-value catch: `no_enum_sort_then_map_values`.** Zero diagnostics, unconditional crash, and it generalises to a whole precise AST class. Runner-up on blast radius: `fix_ets_new_string_name`.

---

### 6. API surface confabulated by plausibility

**Members (23) — the largest cluster:** `undefined_function`, `no_hallucinated_math_fn`, `no_hallucinated_math_round`, `no_hallucinated_math_round2`, `no_hallucinated_map_reduce`, `no_hallucinated_base_hex_encode`, `no_hallucinated_crypto_hex`, `no_hallucinated_crypto_compare`, `no_hallucinated_erlang_warn`, `no_hallucinated_fetch_part`, `no_hallucinated_agent_update_and`, `no_hallucinated_queue_empty`, `no_hallucinated_persistent_term_fn`, `no_hallucinated_naive_datetime_to_unix`, `no_hallucinated_stream_data_string`, `no_process_send_two_args`, `no_list_keystore_three_args`, `no_compile_warn_undefined_module`, `no_hallucinated_struct`, `no_hallucinated_struct_field_in_pattern`, `no_plug_upload_size_field`, `fix_undefined_type_t_in_spec`, `prefer_stdlib_gcd`. **Untested by refutation.**

**Why.** The model's map of the stdlib is generative, not indexed. Names are composed from neighbouring real functions (`:math.ceil` → `:math.round`), from another language's namespacing (Python `math.min`, Ruby `map.reduce`), or by blending two real names (`update/2` + `get_and_update/2` → `update_and/2`).

**The load-bearing asymmetry.** An undefined *qualified remote* call is only a compile **warning** — the module builds, ships, and raises `UndefinedFunctionError` the first time the line runs. An undefined *bare local* (the Python-builtin shape: `len(x)`, `sorted(x)`, `range(0,5)`) is a hard **error** that stops the build. Struct literals and struct keys are the exception: `%Task.ExitError{}` and `%Plug.Upload{size: s}` resolve at compile time and hard-error.

**Detection is free; repair is where the value is — and three repairs are traps.**
- `:crypto.compare/2` → `:crypto.hash_equals/2` raises `ArgumentError` when the two binaries differ in **length**, converting a hallucination into an attacker-triggerable crash on any wrong-length signature. `expected == actual` reintroduces the timing side-channel. The correct repair is length-check-then-`hash_equals`.
- `Base.hex_encode` → the compiler's own "Did you mean" suggests `hex_encode32/1` (base32!). `Base.encode16/1` defaults to `case: :upper`, so a naive repair produces uppercase hex that fails `==` against every canonical lowercase digest.
- `Map.reduce/3` → `Enum.reduce/3` requires re-shaping the callback: passing the original 3-arity fn raises `BadArityError`; "fixing" that to a 2-arity fn without destructuring silently yields `%{{:a, 1} => 1}` — a map with tuple keys and no error anywhere.
- The reverse form matters too: `prefer_stdlib_gcd` shows a hand-rolled Euclidean `gcd` is *not* equivalent to `Integer.gcd/2` — it inherits `rem/2`'s sign, so `gcd(12,-18)` = `-6` vs stdlib `6`. Auto-rewriting is a silent behaviour change.

**Highest-value catch: `no_hallucinated_crypto_compare`** — an auth path that 500s on every request, and uniquely a case where detection alone is *harmful*.

---

### 7. Clause dispatch and source order not modelled — a function treated as a dictionary entry where the newest definition wins

**Members (7):** `no_shadowed_function_redefinition`, `no_unreachable_function_clause`, `no_unreachable_duplicate_function_clause`, `no_split_function_definition`, `no_unused_private_function`, `no_guard_before_validation`, `prefer_head_pattern_over_tail_destructure`. **Untested by refutation.**

**Why.** This is the fingerprint of generation-by-append: the model re-emits a whole clause with a corrected body rather than editing the original, and appends new `handle_call`/`handle_info` clauses at the bottom. It assumes last-write-wins; Elixir dispatches in source order, so the *stale placeholder shadows the intended implementation*.

**Failure modes.** Two clauses with identical patterns — the second (usually the intended one) is dead. Compiler warns `this clause cannot match because a previous clause at line N matches the same pattern`, plus a redundancy type warning; build is green under plain `mix compile`. `no_guard_before_validation` and `prefer_head_pattern_over_tail_destructure` are the same ordering blindness *within* one function: a guard that duplicates a body `raise` makes the descriptive `ArgumentError` dead code and hands callers a `FunctionClauseError` instead; a head that binds `[head | tail]` and then re-destructures `[first|_] = tail` in the body advertises "any non-empty list" while actually requiring two elements — a one-element list gets a mid-body `MatchError` instead of a clean `FunctionClauseError`.

**Highest-value catch: `no_shadowed_function_redefinition`** — the intended implementation is precisely the one that never runs, the symptom is a stale placeholder return value, and the repair (delete or merge the shadowed head) is unambiguous.

---

### 8. Erlang read as if it were Elixir

**Members (7):** `no_atom_as_function_name`, `no_undefined_guard_equality_in_case`*, `no_arrow_operator_outside_comprehension`, `fix_bitwise_infix_operator`, `prefer_double_quoted_atom`, `no_ets_info_bare_size`, `no_exit_two_args`. **Untested by refutation.** (*`no_undefined_guard_equality_in_case` has a false premise — see below — but its real content, `:ets:info(t)`, belongs here.)

**Why.** Everything the model knows about ETS, gen_server, `:queue`, `:lists` and bitwise operators comes from Erlang sources, and Elixir's `:atom`-prefixed remote calls make Erlang look one search-and-replace away. So it transcribes rather than translates.

**Failure modes.** `:ets_table_name(__MODULE__)` — no `:atom(args)` call form, tokenizer failure. `:ets:info(t)` — Erlang `Mod:fun`, parse error at column 5 (verified). `:ets.info(table, size)` — bare lowercase word is an atom in Erlang, a variable in Elixir: `undefined variable "size"`. The near-miss `:ets.info(t, :sizes)` compiles and badargs at runtime. `a <- b()` as assignment — parses (`{:<-, _, [...]}`), then `undefined function <-/2`. `|||`/`&&&`/`<<<` without `import Bitwise` — parses, then `undefined function |||/2`. `:'$end_of_table'` — deprecation warning only, value unaffected. `exit(pid, reason)` — only `Kernel.exit/1` is auto-imported.

**Highest-value catch: `no_exit_two_args`.** Only member whose arity conceals a semantic difference: the compiler says `undefined function exit/2`, and the tempting one-argument repair `exit(:timeout)` compiles fine and kills the **calling** process instead of the target — a build error converted into a silent wrong-process kill.

---

### 9. Guards treated as ordinary boolean expressions

**Members: 2, not 4.** `no_remote_function_in_guard`; `no_mapset_member_in_guard` (a strict duplicate — both matchers accept `cannot invoke remote function MapSet.member?/2 inside a guard`, and byte-identical output on the same input). **Refuted as stated.**

**Corrections from the refutation pass.**
- `fix_regex_in_guard` **ejected**. Its matcher keys on `escaped Regex structs are not allowed in match or guards`, but an inline `~r//` guard raises a *different* message (`invalid expression in guard, the ~r sigil is not allowed in guards`) that the matcher rejects; and its fix only recognises `{:sigil_r, _, _}` AST, so it no-ops on the `@attribute` source that *does* produce its message. It can never match and fix the same file. The message also fires with no guard at all (`def f(@re)`), so it is not guard-scoped.
- `no_in_guard_with_variable_rhs` **ejected**. `in` *is* whitelisted — `x in [1,2,3]` and `x in @attr_list` compile. The failure is an argument-shape restriction (`in` expands to inline comparisons, so the RHS must be compile-time), a different misconception.
- **Missing members that do belong:** `fix_local_function_in_guard`, `no_hallucinated_guard_fn` (`cannot find or invoke local .../1 inside a guard`), `fix_negation_in_guard` (`! is not allowed in guards`).
- **Root cause restated.** It is not purity — `is_map_key(m, :a)` and `map_size/1` are legal in guards while `Map.has_key?/2`, a thin wrapper over the very same `:erlang.is_map_key/2`, is not. The discriminator is *spelling*: guards admit a fixed set of Kernel macros and `:erlang` BIFs the compiler expands inline; the Elixir stdlib module spelling of the same operation is never admitted.

**Highest-value catch:** `no_remote_function_in_guard` — but **not** with the repair the original cluster proposed. "Move the test into the body" is unsound: guards swallow exceptions, bodies do not. Verified: after the rewrite, `A.f(7)` raises `BadMapError` from `Map.has_key?(7, :k)` where the guard version fell through to a later clause. A correct hoist must be wrapped in the corresponding `is_*` test, or the repair must move the test into the *pattern* (the rule's own second branch, `Map.get(v, :__struct__) == Regex` → `%Regex{} = v`, is the only sound repair in the set).

---

### 10. Branch bodies assumed to mutate the enclosing scope

**Members: 5, not 7** (and two of those five are one rule). `fix_if_branch_assignment_scope`, `no_if_assignment_as_statement` + `no_cond_variable_assignment_in_inner_branch` (merge — `extract_both_branches/2`, `extract_kw/2`, `extract_assignment_value/2` are character-identical; only output formatting differs, and the second handles no `cond` at all despite its name), `fix_cond_branch_assignment_in_guard`, `fix_undefined_variable_in_with_else`. **Refuted as stated.**

**Corrections.**
- `fix_cond_branch_assignment_scope` **ejected**: its moduledoc's premise is empirically false. Its own fixture (`wma1_val = cond do ... end` then `wma1_val * 2`) compiles cleanly and returns 12. Its AST predicate matches `{:=, _, [var, block]}` — the already-correct hoisted idiom every other member is trying to *produce*.
- `fix_undefined_variable_in_helper_scope` **ejected**: different root cause. Python raises `NameError` and JS raises `ReferenceError` when a callee reads a caller's local — neither language has caller-frame scoping, so this cannot be transplanted scoping. It is a parameter-threading omission.
- **Attribution narrowed.** Python leaks if-branch assignments; JS leaks only with `var` — `let`/`const` in an `if` block give `ReferenceError`, matching Elixir.
- **Root cause sentence corrected.** "The fix is always `x = if/cond/case ... end`" is false for three members: the guard variant restructures into nested `if`s, the `with/else` variant hoists a clause out of the `with`, and the ejected helper-scope rule changes arity.

**Failure modes.** `if x > 10 do result = :big else result = :small end; result` → `undefined variable "result"` plus two "unused" warnings. `with true <- h != "", sigs = String.split(h, ","), ... else _ -> sigs` → `undefined variable "sigs"`: `else` clauses run in the scope that existed *before* the `with`. Indentation-looking-like-nesting inside `cond` is a separate parser-model error, not a scope-model one — the stab parser is indentation-insensitive and flattens the clauses into siblings.

**Highest-value catch — corrected.** Not `fix_if_branch_assignment_scope`. Its shadowing analysis is right (with `state` bound before the `if`, the conditional becomes a silent no-op and only a "variable is unused (there is a variable with the same name in the context)" warning appears) but the rule is hard-gated on `%{severity: :error}` and the shadowing source emits only warnings — it can only ever fire on the unbound variant, which is already a hard compile error. **The catch worth building is a new warning-severity rule keyed on that "same name in the context" message.** Worst member: `fix_undefined_variable_in_with_else`, whose fix prewalks the whole file lifting `=` clauses out of *every* `with`, verified to manufacture a brand-new `undefined variable "user"` in code that had one bug.

---

### 11. Higher-order stdlib contracts guessed from a neighbouring function

**Members (4):** `fix_string_replace_multi_arity_fn`, `fix_deprecated_map_map`, `no_map_update_zero_default_with_subtraction`, `no_stream_data_constant_with_range`. **Untested by refutation.**

**Why.** When the model knows a function's *name* it fills in the callback contract from the nearest analogue: `Regex.replace`'s capture-group callback onto `String.replace`; a value-returning mapper onto `Map.new`; Python's `random.randint` bounds onto `StreamData.integer`; "the default is the seed the callback starts from" onto `Map.update/4`.

**Failure modes.** `String.replace(s, re, fn m, acc -> ... end, [])` — the replacement must be a binary or arity-1 fn; compiles with only an unused-variable warning, `FunctionClauseError` at runtime (the multi-arity API is `Regex.replace/3`, which also reverses the first two arguments). `StreamData.constant(?a..?z)` generates the `%Range{}` struct itself — property tests pass while testing nothing. `Map.map/2` → `Map.new/2` is a trap for *repair*: verified, `Map.map(%{a: 1}, fn {_k,v} -> v*10 end)` = `%{a: 10}` while `Map.new` with the identical callback raises `ArgumentError`.

**Highest-value catch: `no_map_update_zero_default_with_subtraction`.** Verified silent: `Map.update(%{}, :acct, 0, fn e -> e - 500 end)` returns `%{acct: 0}` — the callback is never invoked for an absent key — while the same call on a present key returns `%{acct: -500}`. Every account is short by exactly its first transaction, zero diagnostics. The invariant is mechanically checkable: *a constant default is only correct when the callback is a fixed-sign accumulation from that operation's identity element*.

---

### 12. Compile-time expansion is invisible

**Members: 3, not 6.** `fix_undefined_nested_module_struct`, `fix_undefined_struct_in_pattern`, `fix_nested_module_short_reference`. **Refuted as stated.**

**Corrections.** `no_plug_before_dependency_definition` ejected — its moduledoc claims it handles `SomeModule.init/1 is undefined` but its actual matcher is `atom cannot be followed by an alias`, a tokenizer error from `plug(:LifecycleApi.Plugs.ApiVersion, ...)`. `no_function_in_module_attribute` ejected — it fails wherever it is written (`cannot escape #Function<...>`; `@f &Mod.fun/1` in the identical position compiles), so it is about attributes-as-compile-time-literals, not ordering. `no_private_fn_called_from_macro_quote` ejected as a distinct hygiene misconception.

**Root cause restated.** "Everything in a file is visible everywhere in it" is not Python's rule either — `class Parent: x = Child()` with `Child` below raises `NameError`. What Python and JS actually give you is *deferred resolution inside function bodies*. Elixir expands `%Struct{}`, aliases, module attributes and macros at **compile time even inside a `def` body**. Appending ordinary helper functions at the bottom is fine in Elixir; only compile-time-expanded constructs break.

**Failure modes.** `%Parent.Child{}` used above `defmodule Child` → `Parent.Child.__struct__/1 is undefined, cannot expand struct`. `%Exit{reason: r}` in a `catch` body where `Exit` is a nested module defined later — same error, definition-order not pattern-matching (the rule's name is a misnomer; the struct is in the clause *body*). `Coordinator.start_link()` above the nested `defmodule Coordinator` — aliases are lexical, so it resolves to top-level `Elixir.Coordinator`; **the build stays green** with only a warning (whose "Did you mean" does name the right module) and the process dies in production with `UndefinedFunctionError`.

**Note the unresolved contradiction:** the two struct members prescribe *opposite* remedies for the same diagnostic — one reorders modules, the other deletes the struct wrapper. Running the latter on a defined-later nested struct turns `{:error, %Outer.Inner{reason: r}}` into `{:error, r}`, deleting a struct that exists.

---

### 13. do/else/after/rescue/catch treated as interchangeable block keywords

**Members: 4, not 6.** `fix_after_clause_pattern_arrow` + `no_if_else_in_receive_after` (mirror halves of "`after` has one shape"), `no_catch_in_receive`, `no_after_or_rescue_in_case`. **Refuted as stated.**

**Corrections.** `no_pin_in_after_clause` ejected — its matcher is `String.starts_with?(msg, "misplaced operator ^")` with no receive/after test; verified it fires on `^y + x` in a module with no `receive` anywhere and strips *valid* pins on the same line, converting a `MatchError` assertion into a rebind. It belongs with the accepted misplaced-pin family. `no_else_in_for_comprehension` is peripheral (with/else vocabulary, not try). The **Python attribution is wrong**: Python's `finally:` takes plain statements — exactly Elixir's `try/after` shape — so a transplant would produce *correct* code. The `->` comes from `receive`'s own `after N ->` and `rescue e ->`. `try do 1 else 1 -> :one end` is valid Elixir, which explains the fusion without any foreign language.

**Why the shape survives generation.** Elixir's parser accepts do/else/catch/rescue/after as generic keyword-block options on *any* call, so all of these **parse** and fail only during expansion — the training signal never punished them at the syntax level.

**Failure modes.** `case x do ... after ... rescue ... end` → parses to `{:case, _, [subj, [do:, after:, rescue:]]}`, then `unexpected option :after in "case"`. `receive do ... catch :exit, _ -> ... after 5_000 -> ... end` → `unexpected option :catch in "receive"`, positioned on `receive`, not on `catch`. `try do ... after {result, new_state} -> body end` → parses, then `misplaced operator ->`; and the variables bound in the fake pattern do not exist, so naively deleting the arrow line leaves `undefined variable` errors. `receive ... after (if ... end) end` with no timeout value → `expected a single -> clause for :after in "receive"`.

**Highest-value catch — corrected to `no_if_else_in_receive_after`.** Its fix invents `after 0 ->`: verified at runtime that a receive so repaired returns `{:error, :timeout}` immediately even though a reply arrives 50 ms later, and it compiles clean so nothing downstream flags it. A silent concurrency-semantics change outranks `no_catch_in_receive`'s catch-deletion (which at least shows in the diff). `no_after_or_rescue_in_case` is **already shipped** as the accepted `Credence.Semantic.FixAfterOrRescueInCase` — not an open gap.

---

### 14. Keyword-list-last, and "`name(args) do…end` is a CALL"

**Members: 3, not 8.** `no_keyword_if_in_tuple` + `fix_mixed_required_optional_map_keys` (identical parser message: *unexpected expression after keyword list. Keyword lists must always come last…*), and `no_bare_function_def_syntax`. **Refuted as stated.**

**Corrections.** Four distinct diagnostic classes were lumped: `fix_do_equals_keyword_syntax` is a reserved-word error (`do` as an assignable identifier); `fix_stray_comma_before_when_guard` + `fix_when_guard_in_for_comprehension` are their own pair under "`when` overgeneralized as a comma-separated filter"; `no_bare_case_in_map` is a non-defect. The Python attribution in `fix_when_guard_in_for_comprehension`'s docstring is false — Python has no `when`, its comprehension filter is `if`, and `for {a,b} when b>1 <- l` **is** valid Elixir (`when` is legal in a generator *pattern*).

**Highest-value catch — corrected to `no_bare_function_def_syntax`.** A function definition emitted without `def`/`defp` parses as a local call of arity N+1 and errors with `undefined function init/2 (there is no such import)` — the arity being one higher than intended is the tell. It shows up overwhelmingly in `Plug.Router` modules, where the surrounding legitimate macro calls (`plug :match`, `get "/ping" do ... end`) have exactly the same call-with-do-block shape. It is the only member that both parses *and* sits in the right phase, and the only one with a demonstrated **silent** path: in a DSL module where an imported macro of the same name/arity exists, the missing-`def` form compiles with no error and defines something else entirely.

The original nomination, `fix_if_inline_else_case_block`, had cross-contaminated error text (its real diagnostic is `misplaced operator ->`, and the quoted "(there is no such import)" belongs to `no_bare_function_def_syntax`) and is inert as filed.

---

### 15. `&` read as "make a callable out of anything"

**Members: 2, not 3.** `fix_invalid_capture_with_literal`, `no_capture_as_identity_function` — sharing one diagnostic (`invalid args for &, expected one of: ... Got: <term>`) and one belief. **Refuted as stated.**

**Corrections.** `no_nested_capture` ejected: different diagnostic (`nested captures are not allowed`) and the *opposite* misconception — in `&Map.update(&1, 0, &(&1 + 1))` the model uses `&1` correctly in both positions; it has capture's meaning right and over-generalises composition. **The Scala/Kotlin attribution is wrong** (Scala uses `_`, Kotlin uses `::method`; neither uses `&`, and Elixir's `&1` is the direct analogue of Scala's `_`, which the model gets right). Ruby explains `&:atom` and `&identifier` only — `&true`/`&false` are TypeErrors in Ruby too and Ruby's `&nil` means "pass no block".

**Failure modes.** `&true`, `&false`, `&nil`, `&:atom` as constant callbacks; `&fn(_r) -> true end` (double capture); `&System.monotonic_time(:millisecond)` as a 0-arity thunk; `&System.os_time(:second/0)` where `:second/0` parses as integer division.

**Highest-value catch — reframed.** `no_capture_as_identity_function` is the most **dangerous** member, not the most valuable: verified, `Enum.map([1,2,3], transform)` = `[2,4,6]` but its output `Enum.map([1,2,3], fn _ -> transform end)` = `[#Function<>, #Function<>, #Function<>]` — a loud compile error turned into a silent logic bug. The `&value` vs `&function` reading is not decidable from source, so no single rewrite is correct. The **coverage gap is real** (verified: `Credence.Semantic.fix` leaves both `&true` and `&x` unchanged, because the live `FixInvalidCaptureWithArguments` claims every "invalid args for &" diagnostic and then no-ops), but the remedy is a narrowed low-priority sibling — the repo already ships that pattern in `FixNegatedCaptureWithArity` at `priority 490` — not displacement.

---

### 16. `|>` assumed to bind tightest

**Members: 2, not 3.** `no_pipe_into_arithmetic_operator`, `no_pipe_into_in_expression` — in fact the same `Macro.pipe` error with a different operator atom. **Refuted as stated.**

**Corrections.** `fix_block_expression_as_pipe_left` ejected: nothing is mis-grouped in `if c do ... end |> {state, &1}` — the RHS is already a single tuple literal, so "parenthesise it" is not even a candidate repair. Its misconception is "`&1` is a positional placeholder that lets me pipe into an arbitrary slot" (R's magrittr `.`, Clojure's `%`), which is the *opposite* mental model.

**Mechanism.** `|>` sits near the bottom of the precedence table (below `* /`, `+ -`, `<> ++ --`, `..`, `in`), so everything to its right becomes one operand: `list |> (Enum.sum() / length(list))`. `Kernel.|>/2` then raises. The compiler's message leads with `cannot pipe list into Enum.sum() / length(list)` — printing the mis-grouped operand verbatim — so it is *less* misdirecting than the original cluster claimed; only the trailing "the :/ operator can only take two arguments" clause is arity-framed.

**Correction to the repair claim.** "Mechanical" is false: the shipped fix admits an operator node as the arithmetic's left operand and prepends the piped value to it, verified to produce `-(x, foo(), bar()) - baz()` — a **parse** error — from `x |> foo() - bar() - baz()`. It downgrades a compile error to a parse error on ordinary left-associative chains. It also covers only `[:+, :-, :*, :/]`, not `<> ++ -- .. in` as claimed.

**Worst member: `no_pipe_into_in_expression`** — the only one in a reachable phase, and its `fix/2` discards the diagnostic and line-regexes the whole file, verified to make a previously-parsing file unparseable.

---

### 17. Pattern position treated as expression position

**Members: 2, not 5.** `no_or_in_case_pattern` (semantic copy), `fix_pin_on_non_variable`. **Refuted as stated.**

**Corrections.** `fix_ets_match_spec_variable_in_comprehension` ejected — verified the error survives with *every* pattern removed (`def f(t), do: :ets.match(t, {name, :_, :"$1"})` still errors), and a match spec can be passed through a variable like any data term. `fix_undefined_variable_in_equality` ejected (a `cond` head is expression-only; the error runs the *other* direction). `fix_rescue_struct_pattern` ejected — Python has no `%` sigil (`except %ValueError:` is a SyntaxError), and `rescue %FunctionClauseError{} ->` *with* braces is also rejected, so it is about `rescue`'s restricted clause grammar, not patterns.

**Failure modes.** `case v do nil or "" -> :empty end` parses and dies with `or is not allowed in patterns` — and `v when v == nil or v == ""` in the *guard* compiles fine, which is exactly why the mistake looks plausible. `^{key}`, `^:ok`, `^%{a: k}`, `^foo()` all parse and fail with `invalid argument for unary operator ^, expected an existing variable`.

**Highest-value catch — corrected to `fix_pin_on_non_variable`, as a hazard.** Its fix *strips* the pin, converting a value comparison into a fresh binding: verified `[^{key}, rest]` → `[{key}, rest]` compiles and matches subject `{999}` against `key = 1`, returning the wrong branch. That directly contradicts the cluster's own root cause, which says the pin belongs one level *deeper* (`{^key}`). Any port must push the pin inward, not delete it.

**Split off:** an inverse cluster — *expression position mistaken for pattern position* — covering `fix_undefined_variable_in_equality` (`cond` is not `case`: `conn.path_info == ["api","uploads", id]` binds nothing; and when an outer `id` exists it compiles clean and compares against the stale value), the ETS match-spec family, and `rescue`'s clause grammar.

---

### 18. OOP object model projected onto Elixir

**Members: 2 + 1, not 5.** Ruby method-syntax transplant: `fix_oop_style_method_call_syntax`, `no_defp_qualified_name`. Python mutable-attribute transplant: `fix_struct_field_assignment_syntax`. **Refuted as stated.**

**Corrections.** `fix_apply_on_function_reference` ejected — no reachable trigger (its matcher wants the literal substring `apply(:call, [])`, which no compiler emits; its headline example emits **zero** diagnostics). `fix_python_style_struct_definition` ejected — `defp struct Node do %{...} end` is not valid Python, Ruby, or any dataclass syntax; it is a hallucinated DSL. **Language attribution corrected:** `def Macro.expand(x):` and `bucket.finalized?(bucket)` are both Python SyntaxErrors (`?` is not a Python identifier char) — they are Ruby singleton-method and predicate syntax. Only `left.right = node` is valid Python. The claim that "most of these compile and fail at runtime" is backwards: 3 of 5 are hard compile errors.

**Highest-value catch — corrected to `fix_struct_field_assignment_syntax`.** It is the only member whose obvious repair converts a loud compile error into code that compiles and is silently wrong: verified, `l = root.left; l = %{l | right: new}` leaves `root.left.right == nil` while `l.right.value == 3` — an AVL rotation silently produces a corrupted tree, because Elixir rebinding does not mutate the aliased copies the imperative original relied on. The original nomination's fix is itself broken: `bucket.finalized?(bucket)` → `bucket.finalized?` trades an `ArgumentError` for a `KeyError`.

---

### 19. Kernel auto-imports and no-overloading unknown

**Members (2):** `no_define_to_string`, `no_import_local_function_conflict`. **Untested.** In Python/Ruby/JS a local definition simply shadows an import; Elixir refuses the ambiguity outright — `imported Kernel.to_string/1 conflicts with local function`, arity-exact, and fires whether the local is defined before or after its call sites. Verified: `def` vs `defp` is irrelevant, and a local with *no* unqualified call site compiles fine. **Highest-value catch: `no_define_to_string`** — `to_string/1` normalisers are a stock LLM helper, and the idiomatic repair (`import Kernel, except: [to_string: 1]`) is exactly the one a generator will not produce; renaming, the obvious alternative, silently changes the module's public surface.

---

### 20. A framework's injected bindings guessed from a sibling framework

**Members (2):** `fix_undefined_params_in_plug_router`, `no_undefined_options_in_plug_router_block`. **Untested.** Plug.Router compiles a route body into `fn var!(conn), var!(opts) -> ...` — the only two injected names are `conn` and `opts`. Generated routers reach for `params[...]` (a Phoenix controller habit) and `options` (the more plausible English word). Since Elixir 1.15 an undefined variable is a hard error, not a parens-less local call, so these at least fail loudly. **Highest-value catch: `fix_undefined_params_in_plug_router`** — appears in essentially every generated webhook/upload router, and the repair is mechanical and total (`params[...]` → `conn.params[...]`), which is the whole value since the compiler already reports the variable precisely.

---

### 21. Version drift

**Members (2):** `prefer_explicit_range_step`, `no_deprecated_not_in`. **Untested.** Warnings only — which sounds harmless until you remember generated code is normally gated by `--warnings-as-errors`, at which point a deprecation is a build failure. **Highest-value catch: `prefer_explicit_range_step`**, the only entry in the whole 140 where following the compiler's own suggestion is *wrong*: for a to-end slice the compiler proposes `3..-1//-1`, which `String.slice/2` and `Enum.slice/2` then reject at runtime ("negative steps are not supported… pass `3..-1//1` instead"). A to-end range becomes `//1`; only a genuinely descending range becomes `//-1`.

---

### 22. Token-level corruption from the decoder

**Members: 2, not 3.** `fix_truncated_module_reference` (`__MODULE%` — a lost `_` before a following `%`), `no_mixed_script_identifier` (`defmodule补偿State`: the space after `defmodule` swallowed, gluing Latin+Han+Latin into one token; Elixir's UTS-39 rule rejects it). **`fix_ets_match_spec_atom_variables` ejected — false premise, see below.** **Untested otherwise.**

These are sampling artefacts, not beliefs about Elixir, and deserve their own class because the consequence is categorically different: the file does not tokenize, so every semantic rule, formatter and compiler pass downstream is blocked. The fix is purely textual. **Highest-value catch: `no_mixed_script_identifier`** — takes out the entire file rather than one expression, is invisible to a human reviewer, repair is a single token edit, and no live rule covers it. Best payoff-to-risk ratio in the set.

---

### 23. No early exit — `return` written as if blocks were statements

**Members: 3, not 6.** `no_bare_return_keyword`, `no_early_return_in_unless`, `no_return_fn_in_conditional`. **Refuted as stated.**

**Corrections.** `no_elif_keyword` and `no_elsif_keyword` **split out** into their own cluster (see 24) — they are branch-keyword vocabulary, not early exit, and their repair *is* local. `no_discarded_unless_value` **dropped**: its input population is produced by an accepted Credence rule one hop upstream, not by an LLM. Minor: `unless` is Ruby/Perl, not Python.

**What survives, and it is the sharpest fact in the whole catalogue.** Bare `return` on its own line parses, then errors `undefined variable "return"` (plus `warning: variable return in code block has no effect`); `return {:error, r}` errors `undefined function return/1`. **Elixir has no early exit at all, so every naive repair — delete the `return` — compiles and then runs exactly the code that was meant to be skipped.** The only correct repair restructures the body into `if/else` (inverting the condition for `unless`) or `with`.

**Highest-value finding: the incumbent, not any rejected rule.** The **accepted, shipping** `Credence.Semantic.NoBareReturnInUnless` performs precisely that naive strip. Verified: its output compiles with zero diagnostics and `U2.f(-5)` returns `{:ok, -5}` when the intent was `{:error, :neg}`. Credence ships a silent behaviour change, and the rule designed to catch the aftermath (`no_discarded_unless_value`) is keyed to a diagnostic Elixir never emits. **Most dangerous rejected member:** `no_early_return_in_unless`, whose fix *inverts branch logic* on the `if` form — `if x < 0 do return {:error,:neg} end / {:ok,x}` becomes `if x < 0 do {:ok, x} else {:error, :neg} end`.

---

### 24. Foreign branch-keyword vocabulary (`elif` / `elsif`)

**Members (2), split out of cluster 23.** `elif b do` tokenizes as a plain call opening a *new* do-block, which swallows the enclosing `if`'s `end`. Verified: the reported error is `missing terminator: end` anchored on the **module's** `do` on line 1, pointing nowhere near the defect. (`no_elif_keyword`'s moduledoc claim of a "cannot invoke def/2 inside function/macro" error is wrong.) The repair is a purely local token→`cond` transliteration.

**Highest-value catch: `no_elif_keyword`** — the only member covering a live gap. The accepted `FixElsifInIfChain` handles `elsif` and leaves `elif` source completely unchanged; `no_elsif_keyword` produces byte-identical output to the accepted rule and has zero value.

---

### 25. Python notation transplanted

**Members: 2, not 5.** `fix_python_spread_in_map` (`%{streams: %{}, **state}` → `syntax error before: '**'`; the Elixir equivalent is `Map.merge/2` or `%{state | ...}`), `fix_python_format_in_string_interpolation` (`"#{cents:02}"` → `keyword argument must be followed by space after: cents_part:` — Elixir's tokenizer reads `identifier:` inside `#{}` as a keyword key; there is no format mini-language). **Refuted as stated.**

**Corrections.** `fix_div_rem` ejected: infix `div`/`rem` is **Erlang**, and the real `//`/`%` transplants ship as separate accepted rules. `fix_map_arrow_in_list_bracket` ejected: `=>` is Erlang/Ruby, and it *is* valid Elixir inside `%{}` — this is an Elixir-internal container generalisation. `no_capture_as_bitwise_and` ejected (already shipped; the evolution copy is a rejected delta).

---

## Already handled by the compiler

30 rules are tagged `compiler-already-catches` and another 18 are outright parse failures — 48 of 140 need no rule at all for *detection*. What follows is the frequency table of what generated Elixir actually gets wrong, ordered by how many rules were written about each diagnostic. This is the most directly useful signal in the corpus for prompt-level correction.

| Compiler diagnostic | rules | severity | notes |
|---|---|---|---|
| `undefined variable "X"` | 17 | error | Scope leakage, underscore drift, framework bindings, Erlang bare atoms, `return`. By far the dominant error. |
| `X.f/N is undefined or private` | 16 | **warning** | Hallucinated APIs. Build stays green; crash at first execution. The "Did you mean" list is wrong or harmful in ≥3 cases. |
| Parse / tokenizer errors | 18 | fatal | Whole file unanalysable — blocks every downstream phase. |
| `undefined function f/N (expected M to define…)` | 9 | error | Missing `def`, `return`, `exit/2`, Bitwise without import, `<-` as assignment, `a div b` regime (b). |
| `X.__struct__/1 is undefined, cannot expand struct X` | 4 | error | Definition order, hallucinated structs. Compile-time expansion, never runtime. |
| Clause-ordering warnings (`should be grouped together`, `cannot match because a previous clause…`) | 4 | **warning** | Silent wrong answer under plain `mix compile`. |
| Deprecations (`Map.map/2`, single-quoted atoms, `not x in y`, implicit range step) | 4 | **warning** | Fatal only under `--warnings-as-errors`, which is how generated code is normally gated. |
| `invalid args for &` / `capture argument &N` / `nested captures are not allowed` | 4 | error | |
| `cannot pipe X into Y` | 3 | error | Message names the mis-grouped operand verbatim. |
| `unexpected option :X in "Y"` (case/receive/cond/with/for) | 3 | error | Precise, but suggests nothing. |
| `cannot invoke remote function M.f/N inside a guard` / `invalid expression in guard` | 4 | error | |
| `imported Kernel.f/N conflicts with local function` | 2 | error | |
| `function f/N is unused` | 3 | **warning** | Misdescribes the defect in the MFA-timer and macro-quote cases. |
| `unknown key :k for struct X` / compile-time `KeyError` | 2 | error | Struct fields resolve at compile time. |

Two structural facts worth carrying forward:

1. **The warning/error boundary is the single most consequential thing about Elixir for generated code.** An undefined *remote* call warns; an undefined *bare local* errors. A duplicate clause warns. A deprecation warns. Everything that warns ships.
2. **Parsing succeeds far more often than intuition suggests.** Elixir's parser accepts `do/else/catch/rescue/after` as generic options on any call, accepts `x.f(args)` as a remote call, accepts `a div b` as `a(div(b))`, accepts `&identifier`, `^{key}`, `nil or "" ->`, `case` as a map value, and `n & 1` as `n(&1)`. Verified in this session for all of them. **Nothing that parses belongs in a parse-failure-gated phase.**

---

## False premises — what the rule generator itself got wrong

26 of 140 rules are wrong *about Elixir*, not merely wrong as engineering. This is a catalogue of the rule-writing model's own misconceptions, and it maps almost one-for-one onto the misconceptions in the code it was auditing.

### A. Premise inverted — the construct is correct Elixir

1. **`fix_ets_match_spec_atom_variables`** — claims `:'$1'` is unparseable and must become the charlist `~c"$1"`. Verified: `Code.string_to_quoted(":'$1'")` → `{:ok, :"$1"}` (deprecation warning only), and `:'$1' == :"$1"` is `true`. `:"$1"` *is* the correct ETS match-spec variable; charlists are never correct there. Both halves of the premise are backwards. The real defect in the field sample was an unterminated atom `:'_}`.
2. **`no_bare_case_in_map`** — claims a bare `case` as a map value is ambiguous with `=>` and "may choke older parsers". Verified: parses, and `%{val: case x do :a -> 1 end, z: 1}` evaluates to `%{z: 1, val: 1}`. `mix format` accepts it and does **not** add the parentheses the rule inserts.
3. **`no_undefined_guard_equality_in_case`** — claims `x when x == :ok ->` is a defect. Verified: zero diagnostics, evaluates to `{:eq, :ok}`. The real defect on the same source line was `:ets:info(table)` — Erlang `Mod:fun` syntax, a parse error at column 5.
4. **`fix_cond_branch_assignment_scope`** — moduledoc claims `wma1_val = cond do ... end` followed by `wma1_val * 2` produces `undefined variable`. It compiles cleanly and returns 12. The rule's AST predicate matches the *already-correct* hoisted form.
5. **`no_date_utc_today_with_arg`** — claims `Date.utc_today/1` is hallucinated. Verified: `[utc_today: 0, utc_today: 1]`. The real defects are the argument type (a calendar *module*) and the return type (`%Date{}`, not a tuple).
6. **`fix_oop_style_method_call_syntax`** — claims `bucket.finalized?(bucket)` is a "compile-blocking syntax error". Verified: it parses.
7. **`no_capture_as_identity_function`** — moduledoc: "a bare `&identifier` always fails to parse". Verified: `Map.update!(m, :key, &new_value)` → `{:ok, ...}`.
8. **`fix_python_spread_in_map`** — moduledoc: "`**` is not a valid operator in any other Elixir context, so `%{...**...}` is unambiguous". Verified: `2 ** 3` = 8, `%{r: base**exp}` parses. The rule rewrites exponentiation into `Map.merge/2`.
9. **`fix_deprecated_map_map`** — states the `Map.map`/`Map.new` callback contract **backwards**. Verified: `Map.map(%{a: 1}, fn {_k,v} -> v*10 end)` = `%{a: 10}`; `Map.new` with the identical callback raises `ArgumentError`.

### B. Matcher keyed to a diagnostic Elixir never emits — inert by construction

10. **`no_discarded_unless_value`** — matches `severity: :warning` + "unless expression result is unused". Verified: the source compiles with `DIAGS: []`. The rule can never fire.
11. **`no_underscore_pattern_binding_with_bare_body_use`** — regex `variable "_\w+" is unused`. Verified: `def f(_a, _unused), do: :ok` produces **zero** diagnostics. The underscore *is* the suppression; Elixir's only underscore warning is `the underscored variable "_x" is used after being set`, which the regex rejects.
12. **`fix_apply_on_function_reference`** — requires the literal substring `apply(:call, [])`. The real 1.20 warning is `incompatible types given to Kernel.apply/3`, and the headline example emits nothing at all. Its green test hardcodes a fabricated message.
13. **`fix_nested_module_short_reference`** — requires `"redefining module"`. The real diagnostic is `Coordinator.get_state/1 is undefined (module Coordinator is not available or is yet to be defined)`. The only message that *can* reach it is an unrelated duplicate-definition warning.
14. **`fix_undefined_nested_module_struct`** — requires `"is undefined (module"` AND `"is not available)"`. The real message is `X.__struct__/1 is undefined, cannot expand struct X` — no `(module` clause; and the module-not-available form now reads `is not available or is yet to be defined)`, so the second substring never appears either.
15. **`fix_regex_in_guard`** — matches `escaped Regex structs are not allowed…` but the inline-sigil case raises `invalid expression in guard, the ~r sigil is not allowed in guards`, which the matcher rejects; and its fix only recognises sigil AST, so it no-ops on the source that produces its message. It can never match and fix the same file.

### C. Cross-language attribution wrong

16. **`no_defp_qualified_name`** — "valid Python but invalid Elixir syntax". Python rejects `def Macro.expand(x):`. It is Ruby singleton-method syntax.
17. **`fix_when_guard_in_for_comprehension`** — blames Python. Python has no `when`; its comprehension filter is `if`. And `for {a,b} when b>1 <- l` *is* valid Elixir.
18. **`fix_after_clause_pattern_arrow`** — "Python/JS finally-ism". Python's `finally:` takes plain statements, exactly Elixir's `try/after` shape — a transplant would produce *correct* code. The `->` comes from `receive`'s own `after N ->`.
19. **`fix_rescue_struct_pattern`** — blames Python `except Type:`. Python has no `%` sigil; `except %ValueError:` is a SyntaxError.
20. **`fix_div_rem`** — "LLMs translate Python's `//` as `expr div expr`". Infix `div`/`rem` is Erlang; `a div b` is a Python SyntaxError. The real `//`/`%` transplants are separate accepted rules.
21. **The underscore family** (`fix_undefined_underscored_binding` + 2 copies) — root cause given as a Go/Python/ESLint lint-annotation transplant. Python behaves *identically* to Elixir: `(a, _b) = t; return b` raises `NameError`. Go's `_` cannot be read at all. Nothing was transplanted; `_x`-for-unused is native Elixir convention that Elixir's own warning text teaches verbatim. The real mechanism is head/body naming drift.

### D. Two unrelated failures fused behind one diagnostic

22. **`fix_unmatchable_tuple_destructure`** — the described bug (`{x, _} = DateTime.to_unix(...)`, a scalar destructured as a tuple) compiles cleanly and raises `MatchError`; the diagnostic it keys on, `misplaced operator |/2`, is produced by something else entirely (`|` outside cons/map-update).
23. **`fix_bitwise_infix_operator`** — the "real diagnostic" fixture is about `<->`, an operator that does not exist in Elixir at all. The rule matched only because the echoed source line happened to contain `|||`.
24. **`no_plug_before_dependency_definition`** — moduledoc describes compile-ordering of module plugs; the matcher is `atom cannot be followed by an alias`, a tokenizer error from `plug :Foo.Bar.Baz`. Its fix reorders the modules and leaves the `:` in place, so the output still does not parse.
25. **`no_unreachable_duplicate_function_clause`** — keys on `no match of right hand side value: [:notifications_server, :timeout_ms]`, a compile-time `MatchError` with nothing to do with duplicate clauses.
26. **`no_hallucinated_fetch_part`** — fuses a hallucinated `Plug.Conn.fetch_part/2` with an unrelated `defp init/1` behaviour-callback warning from the same generated router.

### E. Systemic defects the clustering never detected

Three failure modes recur across dozens of rules and matter more than any individual premise:

- **Wrong phase — inert by construction.** `Credence.Syntax.analyze/fix` run only when `Sourceror.parse_string/1` **fails**. At least 14 rules were filed there for constructs that parse: `no_arrow_operator_outside_comprehension`, `no_after_or_rescue_in_case`, `no_bare_case_in_map`, `no_bare_atom_in_genserver_start_link`, `no_capture_as_identity_function`, `no_nested_capture`, `fix_oop_style_method_call_syntax`, `fix_struct_field_assignment_syntax`, `no_defp_qualified_name`, `no_or_in_case_pattern` (syntax copy), `fix_pin_on_non_variable`, `no_pipe_into_arithmetic_operator`, `fix_block_expression_as_pipe_left`, `fix_if_inline_else_case_block`. Their green tests pass only by calling `analyze`/`fix` directly, bypassing the phase.
- **Unguarded global regex fixes with no parse gate.** The syntax driver reduces `rule.fix(src)` over *every* rule on any unparseable file. Confirmed corruptions: `"see :setup(opts)"` → `"see setup(opts)"`; `@doc "maps %Config -> %Result"` → `"maps e in Config -> %Result"`; a `@moduledoc` line `node.left = other` → `node = %{node | left: other}`; `msg = "pass &handler to the pipeline"` → `"pass fn _ -> handler end to the pipeline"`; a comment containing the target pattern rewritten so the whole file becomes unparseable. In one end-to-end run, a file with exactly **one** genuine parse error emerged with **three corruptions per one repair** and the failure relocated from line 9 to line 2.
- **Dispatch shadowing.** `find_matching_rule` is `Enum.find` over rules sorted by `{priority, module}`, all at default `priority 500`. Broad matchers swallow diagnostics from narrower siblings: `FixEtsMatchSpecVariableInComprehension` claims every `undefined variable "…"`; `FixInvalidCaptureWithArguments` claims every `invalid args for &` and then no-ops; `FixCaseBranchAssignmentScope` claims `undefined variable "return"`. Three of the four underscore rules are byte-identical below the moduledoc and only the alphabetically-first can ever execute. The coexistence pattern exists and works — `FixNegatedCaptureWithArity` at `priority 490` with a narrowed matcher — and should be the template.
- **`match?` reads disk, `fix` rewrites memory.** Several rules gate `match?` on `File.read(diagnostic.file)`, but `RuleHelpers.compile_and_capture/1` compiles with the pseudo-path `"credence_check.ex"`, which exists nowhere. `File.read` returns `{:error, :enoent}` and the rule silently never fires.

---

## What is worth building

> **⛔ SUPERSEDED as a work list (2026-07-28).** Per the header warning, this
> ranking did not survive adversarial review (0 of 12 cluster narratives did),
> and rewriting it is itself a tracked task — `docs/22-remaining-work.md`
> **T5.8**. The honest net product of the 143 is ~6 rules to build and 2 lines
> to widen (docs/18 §5); the verified rebuild specs live in
> `docs/18-per-rule-verdicts.json`'s `action` fields. The per-mode executed
> evidence below remains sound; use it as evidence, not as an order of work.

Ranked by consequence severity — how bad the failure is and how invisible — not by how many rules were written about it. Phase in brackets.

1. **`Map.*` applied to an `Enum.*`/`Stream.*` result** *[pattern/AST]*. From `no_enum_sort_then_map_values`. Zero diagnostics (verified `[]`), unconditional `BadMapError` on every input. Cheap, precise AST check; generalises across `values/1`, `keys/1`, `get/2`, `fetch/2`, `put/3`. Extend to `Map.get/2,3` on a keyword-list parameter (`Map.get([], :k)` raises even on the empty default).
2. **`send(self(), …)` inside a `Task.*`/`spawn` closure** *[pattern/AST]*. From `no_send_self_in_task`. Completely silent, verified; one-line repair (`parent = self()` outside). Highest fix-safety-to-value ratio in the set.
3. **Reply-protocol violations in `handle_call`/`handle_cast`** *[pattern/AST]*. Union of `no_raw_send_in_genserver_handle_call`, `no_send_to_from_in_handle_call`, `no_genserver_reply_in_handle_cast`, `no_genserver_reply_in_handle_call`. Detect: `from` destructured as `{pid, _}`; `send/2` to a pid derived from `from`; `GenServer.reply/2` with a non-`from` first argument. Consequences are hangs and cross-talk, nothing is logged, and no live rule mentions `GenServer.reply` at all. Report-only is sufficient; the repair (`GenServer.reply(from, r)`) is safe but the surrounding restructure sometimes is not.
4. **OTP callback return shapes** *[pattern/AST]*. `Agent.update` callback returning `{:ok, state}` (verified: call returns `:ok`, state silently becomes `{:ok, %{count: 1}}`); `init/1` returning a bare map/struct/atom. Both verified to emit zero diagnostics. Structural, decidable, safely repairable.
5. **`:infinity` reaching `Process.send_after/3,4`** *[pattern/AST]*. Include the `Keyword.get(opts, :key, :infinity)` dataflow — the literal case is visible in review, the default-path case is not. Repair is a clause split (`defp schedule(:infinity), do: :ok`).
6. **`Map.update/4` with a constant default and a non-monotone callback** *[pattern/AST]*. Verified silent and off-by-one-transaction. Checkable invariant: the default must equal what the callback would produce from the operation's identity element.
7. **ETS argument discipline** *[pattern/AST]*. `:ets.new/2` first arg not an atom; flattened `:keypos`; `:private` + `:named_table` combined with a public API function that reads the table. All verified to compile with zero diagnostics; all present as supervisor restart loops rather than ETS errors.
8. **Mixed-script / truncated identifiers** *[syntax — the one place the parse-failure gate is correct]*. From `no_mixed_script_identifier`, `fix_truncated_module_reference`. Blocks the entire file and every downstream phase; invisible to human review; single-token repair; no live rule covers it.
9. **Hallucinated remote calls where the correct repair is non-obvious** *[semantic]*. Detection is free (the compiler warns); the value is entirely in the repair table. Encode at minimum: `:crypto.compare/2` → length-check + `:crypto.hash_equals/2` (never a bare rename, never `==`); `Base.hex_encode` → `Base.encode16(x, case: :lower)`; `Map.reduce/3` → `Enum.reduce/3` **with the callback re-shaped to `fn {k,v}, acc`**; `:math.round` → `Kernel.round/1`; `Agent.update_and/2` → `Agent.get_and_update/2` (ignore the compiler's suggestion, which points at `update/2..5`); `NaiveDateTime.to_unix` → `DateTime.to_unix(DateTime.from_naive!(…))` (dropping the arity does not help — `to_unix/1` is equally undefined); `StreamData.alpha_string/0` → `StreamData.string(:alphanumeric)`.
10. **Implicit descending range step** *[semantic]*. `prefer_explicit_range_step`. The only entry where following the compiler's suggestion breaks the program at runtime; a rule that knows to-end → `//1` and descending → `//-1` is strictly better than the compiler.
11. **Guard-whitelist violations** *[semantic]*. `no_remote_function_in_guard`, folding in `no_mapset_member_in_guard`, `fix_local_function_in_guard`, `no_hallucinated_guard_fn`, `fix_negation_in_guard`. **Report-only, or pattern-move repair only.** Do not ship the body-hoist repair: guards swallow exceptions and bodies do not, verified to convert a fall-through into a `BadMapError`, and the existing implementation additionally deletes catch-all clauses.
12. **Branch-shadowing conditional that is a silent no-op** *[semantic, warning-severity]*. A **new** rule keyed on `variable "X" is unused (there is a variable with the same name in the context)` correlated with a same-named assignment inside an `if`/`cond`/`case` branch. Verified: the code compiles and silently reads the pre-`if` value, so the whole conditional is inert. No existing member can reach it — every one is gated on `severity: :error`.
13. **`elif`** *[syntax — genuine parse failure, correct phase]*. The only confirmed uncovered gap in the live pipeline: the accepted `FixElsifInIfChain` handles `elsif` and leaves `elif` byte-for-byte unchanged. Local token→`cond` transliteration. `no_elsif_keyword` is a byte-identical duplicate of the accepted rule and should simply be deleted.

**Two fixes to shipped code that outrank most of the above.**

- **`Credence.Semantic.NoBareReturnInUnless` ships a silent behaviour change.** It performs exactly the naive `return`-strip that makes the code compile and then execute the branch it was meant to skip. Verified: output compiles with zero diagnostics and returns `{:ok, -5}` where `{:error, :neg}` was intended. It should be report-only until it can restructure into `if/else`.
- **`Credence.Semantic.NoCaptureAsBitwiseAnd` emits unparseable output on hex literals.** Verified in the shipped copy: `flags & 0xFF` → `Bitwise.band(flags, 0)xFF`, because the operand regexes stop at the `0` of `0xFF`.

**Two rules to write nothing about, and delete outright:** `no_bare_case_in_map` and `no_undefined_guard_equality_in_case` target correct Elixir. `fix_ets_match_spec_atom_variables` targets correct Elixir and would replace the *right* value with a wrong one.

**One standing constraint for anything built from this list.** Every fix must be AST-scoped and gated on the parser-reported position, and every fix's output must be re-parsed before acceptance. The verified corruption record — string literals, `@doc` heredocs, comments, and unrelated functions rewritten across a dozen rules — is a property of whole-file regex repair, not of any individual rule's logic.