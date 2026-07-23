# Followup — rules needing human attention

Stage 1 (`stage_1_promote_fixable_rules/review_loop.sh`) appends one section per
set it could not safely promote: no safe fix, duplicate, needs a shared-file
change, type change, or inconclusive. Each entry lists the set's files and the
one-line reason. Work these by hand later.

_No open items._

<!--
Resolved 2026-06-17 — test/pattern/assumptions_filtering_test.exs: NOT an orphan.
It is an end-to-end integration test for the assumptions/switch-filter subsystem
(`:strict`/`:default`/per-switch promises) through the public API — the loop's
per-rule orphan detector false-positived because there is no same-named rule
file. Passes (9 tests) and carries unique coverage (config-precedence changing
real `fix` output; the "filtered rule named in an explicit rules: list warns but
stays filtered" path). Kept. Optional tidy: move to test/ level (alongside
assumptions_test.exs / credence_test.exs) and rename the module off `.Pattern`
so a future scan won't re-flag it.
-->
## fix_string_replace_multi_arity_fn — 2026-07-22
- Files:
  - `lib/pattern/fix_string_replace_multi_arity_fn.ex`
  - `test/pattern/fix_string_replace_multi_arity_fn_check_test.exs`
  - `test/pattern/fix_string_replace_multi_arity_fn_equivalence_test.exs`
  - `test/pattern/fix_string_replace_multi_arity_fn_fix_test.exs`
- Reason: false premise — String.replace/3 is /4 with default [], so removing [] leaves the flagged arity-2 crash fully intact (verified: both raise identical FunctionClauseError); fix does not repair what check flags and the message/moduledoc assert wrong Elixir semantics

## prefer_head_pattern_over_tail_destructure — 2026-07-22
- Files:
  - `lib/pattern/prefer_head_pattern_over_tail_destructure.ex`
  - `test/pattern/prefer_head_pattern_over_tail_destructure_check_test.exs`
  - `test/pattern/prefer_head_pattern_over_tail_destructure_equivalence_test.exs`
  - `test/pattern/prefer_head_pattern_over_tail_destructure_fix_test.exs`
- Reason: every firing case changes MatchError to FunctionClauseError on a 1-element/improper list (accepted rules treat a different exception as a different answer; no assumptions declared), so the safe core is empty without a guard-rewrite redesign; also unfixed collision bugs: inner-head name reused (e.g. [a|b] with [a|_]=b yields unifying [a, a | _rest]), repeated _rest unifies across two fixed params, and rescue blocks referencing the tail var are not checked.

## prefer_stdlib_gcd — 2026-07-22
- Files:
  - `lib/pattern/prefer_stdlib_gcd.ex`
  - `test/pattern/prefer_stdlib_gcd_check_test.exs`
  - `test/pattern/prefer_stdlib_gcd_equivalence_test.exs`
  - `test/pattern/prefer_stdlib_gcd_fix_test.exs`
- Reason: every firing case diverges under :strict — hand-rolled gcd returns sign-carrying results (gcd(-4,0)=-4 vs Integer.gcd=4; verified for all negative pairs) and raises ArithmeticError vs FunctionClauseError on non-integers, with no assumptions declared and no applicable switch (negative ints are a plain-value gap, not rare text), so the safe core is empty without a caller-guard-analysis redesign; the fix is also unsound on its own terms: it deletes the defp pair but only rewrites calls whose args are both bare vars, leaving calls like gcd(a * b, b) (or &gcd/2 captures, or extra gcd clauses outside the consecutive pair) dangling against a now-undefined function.

## fix_apply_on_function_reference — 2026-07-22
- Files:
  - `lib/semantic/fix_apply_on_function_reference.ex`
  - `test/semantic/fix_apply_on_function_reference_check_test.exs`
  - `test/semantic/fix_apply_on_function_reference_fix_test.exs`
- Reason: matches a fabricated diagnostic — Code.with_diagnostics emits nothing for apply(fun_ref, :call, []) (compiles clean; runtime-only ArgumentError whose message also lacks "apply(:call, [])"), so match? can never fire on real input and the rule is unreachable dead code; the fix is also broken independently (rebuilds receiver with [] args so apply(s.get_clock(x), :call, []) drops x; MatchError on single-element dot receivers like apply(f.(), :call, []); whole-file rewrite ignoring the diagnostic line; misrewrites module-valued fields where apply(cfg.mod, :call, []) validly calls cfg.mod.call/0)

## fix_bitwise_infix_operator — 2026-07-22
- Files:
  - `lib/semantic/fix_bitwise_infix_operator.ex`
  - `test/semantic/fix_bitwise_infix_operator_check_test.exs`
  - `test/semantic/fix_bitwise_infix_operator_fix_test.exs`
- Reason: matches a fabricated diagnostic — bare bitwise infix operators (|||, &&&, <<<, >>>, ~~~, ^^^) all parse fine without import Bitwise (verified on Elixir 1.20: they emit "undefined function |||/2"-style errors, never "syntax error"), so match? can only fire on unrelated syntax errors whose quoted snippet happens to contain the token (the test's own @real_diag is really a <-> error); the rule is also internally contradictory — any genuine syntax-error diagnostic means Sourceror.parse_string fails, so fix is a guaranteed no-op on every input match? admits (flag-without-fix), and the claimed companion FixErlangBitwiseBif does not exist; retargeting to the real undefined-function diagnostic would be a redesign, not a narrowing

## fix_cond_branch_assignment_in_guard — 2026-07-23
- Files:
  - `lib/semantic/fix_cond_branch_assignment_in_guard.ex`
  - `test/semantic/fix_cond_branch_assignment_in_guard_check_test.exs`
  - `test/semantic/fix_cond_branch_assignment_in_guard_fix_test.exs`
- Reason: unreachable in production — match? requires reading diag.file, but the pipeline compiles in-memory (file: "credence_check.ex", nonexistent, File.read fails → match? always false; tests pass only via fabricated tmp-file diagnostics); and even a message-only match? is shadowed by FixCaseBranchAssignmentScope, which claims every `undefined variable "…"` diagnostic and sorts first at equal priority 500 in the single-rule-per-diagnostic dispatch — making it reachable needs folding into that accepted rule or a phase change, both outside this set; fix also silently deletes cond branches other than the assign/guard/true trio

## fix_cond_branch_assignment_scope — 2026-07-23
- Files:
  - `lib/semantic/fix_cond_branch_assignment_scope.ex`
  - `test/semantic/fix_cond_branch_assignment_scope_check_test.exs`
  - `test/semantic/fix_cond_branch_assignment_scope_fix_test.exs`
- Reason: unreachable in production — match? needs File.read(diag.file) but the pipeline compiles in-memory (file "credence_check.ex" never exists, so match? is always false; tests fabricate tmp-file diagnostics), and a message-only match? is shadowed by accepted FixCaseBranchAssignmentScope, which claims every `undefined variable` diagnostic and sorts first at equal priority 500 in single-rule dispatch; winning priority would instead shadow/regress that accepted rule since identical messages make the shapes indistinguishable at match? time — reachability requires folding into FixCase or a phase change, both outside this set

## fix_deprecated_map_map — 2026-07-23
- Files:
  - `lib/semantic/fix_deprecated_map_map.ex`
  - `test/semantic/fix_deprecated_map_map_check_test.exs`
  - `test/semantic/fix_deprecated_map_map_fix_test.exs`
- Reason: fix changes the answer on every input it rewrites — Map.map/2's callback returns the new value while Map.new/2's must return a {k, v} pair, so the rename-only rewrite is wrong even on its own test case (verified: Map.map gives %{a: {:a, [3,2,1]}}, Map.new gives %{a: [3,2,1]}); the correct wrapped rewrite (Map.new(m, fn {k, v} -> {k, body} end)) still breaks struct receivers (Map.map(%URI{}, f) works, Map.new raises Protocol.UndefinedError — verified) and the exact :maps.map alternative changes exception class on non-maps; moreover the diagnostic is already claimed by accepted UndefinedFunction (its regex matches every "Mod.fun/arity is deprecated" warning; at equal priority 500 this rule sorts first — FixDeprecatedMapMap < UndefinedFunction — and would steal the diagnostic, suppressing/renaming that rule's reported issue), so the proper home is a new wrap-callback replacement type in UndefinedFunction's @qualified_replacements — an out-of-set change; the only bulletproof standalone core (plain map-literal receiver, literal non-__struct__ keys, single-clause fn with plain-var key) is too narrow to justify the dispatch takeover.

## fix_ets_match_spec_atom_variables — 2026-07-23
- Files:
  - `lib/semantic/fix_ets_match_spec_atom_variables.ex`
  - `test/semantic/fix_ets_match_spec_atom_variables_check_test.exs`
  - `test/semantic/fix_ets_match_spec_atom_variables_fix_test.exs`
- Reason: premise inverted — :'$1' is a valid Elixir atom and the CORRECT ETS match spec variable (≡ :"$1"), while ~c"$1" is the literal charlist [36,49]; verified the fix breaks working selects (atom spec returns [true], charlist spec returns [] on the same table) and is an atom→charlist type change; the fix-test input already parses (rule rewrites never-broken code) and :'$N' cannot produce the "unexpected token: $" diagnostic it claims to fix, so no safe core exists under this rule's design

## fix_ets_match_spec_variable_in_comprehension — 2026-07-23
- Files:
  - `lib/semantic/fix_ets_match_spec_variable_in_comprehension.ex`
  - `test/semantic/fix_ets_match_spec_variable_in_comprehension_check_test.exs`
  - `test/semantic/fix_ets_match_spec_variable_in_comprehension_fix_test.exs`
- Reason: unreachable in production — its target diagnostic is exactly `undefined variable "name"`, which accepted FixCaseBranchAssignmentScope claims first (both priority 500, C sorts before E, single-rule dispatch has no fall-through; verified: find_matching_rule returns FixCaseBranchAssignmentScope for this rule's own flagship input), and winning priority would shadow/regress that accepted rule since the messages are indistinguishable at match? time (same dead-end as fix_cond_branch_assignment_scope, f09370d); additionally the plain-assignment fix emits compiling-but-broken code (verified: `{:"$1", :"$1"}` forces key==value and returns [] where `{:"$1", :"$2"}` returns [[:k, 1]]; the rewritten LHS `[{:"$1", _}]` raises MatchError because :ets.match returns lists of binding lists, not tuples; and `evicted_key = :"$1"` binds the literal atom, so the later :ets.delete removes the wrong key) — reachability requires folding into FixCaseBranchAssignmentScope or a dispatch/phase change, both outside this set

## fix_ets_new_string_name — 2026-07-23
- Files:
  - `lib/semantic/fix_ets_new_string_name.ex`
  - `test/semantic/fix_ets_new_string_name_check_test.exs`
  - `test/semantic/fix_ets_new_string_name_fix_test.exs`
- Reason: unreachable in production — matches a fabricated diagnostic ("table name to :ets.new/2 — use atom interpolation") that the Elixir compiler never emits; verified the flagship input compiles with zero diagnostics (:ets.new arg misuse is runtime-only ArgumentError), so no match? anchor exists and a pattern-phase rewrite would be a different kind outside this set; fix regex also converts any `"#`-prefixed string literal on the flagged line to an atom (type change)

## fix_if_branch_assignment_scope — 2026-07-23
- Files:
  - `lib/semantic/fix_if_branch_assignment_scope.ex`
  - `test/semantic/fix_if_branch_assignment_scope_check_test.exs`
  - `test/semantic/fix_if_branch_assignment_scope_fix_test.exs`
- Reason: dead in production — pipeline diagnostics carry file "credence_check.ex" (nonexistent, so match?'s File.read always fails) and FixCaseBranchAssignmentScope (same priority 500, sorts first, message-only match?) claims every undefined-variable diagnostic first-match-wins; fixing requires folding if-hoisting into the case rule or a phase change, both outside this set

## fix_invalid_capture_with_literal — 2026-07-23
- Files:
  - `lib/semantic/fix_invalid_capture_with_literal.ex`
  - `test/semantic/fix_invalid_capture_with_literal_check_test.exs`
  - `test/semantic/fix_invalid_capture_with_literal_fix_test.exs`
- Reason: dead in production — duplicate match? of accepted FixInvalidCaptureWithArguments (identical "invalid args for &" + :error, same priority 500, Arguments sorts first) which claims every such diagnostic first-match-wins in both analyze and fix with no fallback; making Literal live means re-prioritizing over Arguments (killing that accepted rule, since Literal no-ops on the &call(args)/0 shape) or folding the two rules — out of scope for this set. Its fix also mangles valid captures (&String.upcase(&1) → fn -> String.upcase(&1) end, no capture-ref guard in the dot-call clause).

## fix_nested_module_short_reference — 2026-07-23
- Files:
  - `lib/semantic/fix_nested_module_short_reference.ex`
  - `test/semantic/fix_nested_module_short_reference_check_test.exs`
  - `test/semantic/fix_nested_module_short_reference_fix_test.exs`
- Reason: rule targets the wrong diagnostic — nested-module short references emit "X is undefined" warnings, never "redefining module"; the diagnostics match? does admit (real redefinitions) are unfixable by prefix-qualifying references, so no safe core exists

## fix_python_style_struct_definition — 2026-07-23
- Files:
  - `lib/semantic/fix_python_style_struct_definition.ex`
  - `test/semantic/fix_python_style_struct_definition_check_test.exs`
  - `test/semantic/fix_python_style_struct_definition_fix_test.exs`
- Reason: collides with accepted fix_cyclic_struct_reference — both match the byte-identical "__struct__/1 is undefined" diagnostic, dispatch is winner-take-all by priority with no source access in match?, so at priority 400 this rule steals cyclic-reference diagnostics and breaks that rule's e2e test (priority >500 would make it permanently dead instead); coexistence needs a shared dispatch change or folding into the existing rule

## fix_regex_in_guard — 2026-07-23
- Files:
  - `lib/semantic/fix_regex_in_guard.ex`
  - `test/semantic/fix_regex_in_guard_check_test.exs`
  - `test/semantic/fix_regex_in_guard_fix_test.exs`
- Reason: dead in production — match? keys on "escaped Regex structs..." (emitted only by @attr-regex in guards/patterns, where fix no-ops: no sigil_r in AST), while the sigil-in-guard shape the fix rewrites emits "invalid expression in guard, the ~r sigil is not allowed in guards" which match? never matches; fix also deletes non-regex clauses (catch-all) breaking dispatch intent — needs retarget + transform rewrite

## fix_struct_update_on_dynamic_variable — 2026-07-23
- Files:
  - `lib/semantic/fix_struct_update_on_dynamic_variable.ex`
  - `test/semantic/fix_struct_update_on_dynamic_variable_check_test.exs`
  - `test/semantic/fix_struct_update_on_dynamic_variable_fix_test.exs`
- Reason: fix asserts a struct type the checker explicitly could not prove — no safe core: wrapping the binding with a struct pattern raises MatchError on valid runs where the value is legitimately non-struct on a path that skips the update (diagnostic fires precisely when type is unproven); additionally %__MODULE__{} is wrong when the warning fires outside the struct's module (verified on 1.20: fires in Consumer for %AutocompleteTrie{} update → fix inserts %Consumer{} → __struct__ undefined compile error), prewalk wraps every same-named assignment file-wide instead of the from:-position the message provides, and the parameter-variant message ("trie" repro) matches but is unfixable → whole-file Sourceror reformat with no fix

## fix_undefined_nested_module_struct — 2026-07-23
- Files:
  - `lib/semantic/fix_undefined_nested_module_struct.ex`
  - `test/semantic/fix_undefined_nested_module_struct_check_test.exs`
  - `test/semantic/fix_undefined_nested_module_struct_fix_test.exs`
- Reason: duplicate of accepted fix_cyclic_struct_reference — its match? ("__struct__/1 is undefined") is a strict superset of this rule's diagnostic and its AST-based, compile-verified reorder already produces the exact output this set's tests expect; keeping both would double-attribute the same diagnostic, and this line-based variant is strictly weaker (fragile do/end depth counting, no compile check) — drop.

## fix_undefined_params_in_plug_router — 2026-07-23
- Files:
  - `lib/semantic/fix_undefined_params_in_plug_router.ex`
  - `test/semantic/fix_undefined_params_in_plug_router_check_test.exs`
  - `test/semantic/fix_undefined_params_in_plug_router_fix_test.exs`
- Reason: dead in production — accepted FixCaseBranchAssignmentScope also matches `undefined variable "params"` and sorts first, so Enum.find (first-wins, no fall-through) routes every such diagnostic to it and this rule never fires; deconflicting needs a shared lib/semantic.ex change. (Also the fix is an unsafe whole-file regex that corrupts strings/comments/legit `params` bindings and adds undefined `conn` outside routers.)

## fix_undefined_struct_in_pattern — 2026-07-23
- Files:
  - `lib/semantic/fix_undefined_struct_in_pattern.ex`
  - `test/semantic/fix_undefined_struct_in_pattern_check_test.exs`
  - `test/semantic/fix_undefined_struct_in_pattern_fix_test.exs`
- Reason: dead in production — accepted fix_cyclic_struct_reference's match? ("__struct__/1 is undefined") is a strict superset and sorts first (C<U, both priority 500), so Enum.find (first-wins) routes every such diagnostic to it and this rule never fires; deconflicting needs a shared lib/semantic.ex change. (Also the fix discards the struct wrapper — %Exit{reason: reason} → reason — changing behavior, vs the accepted rule's compile-verified reorder.)

## fix_undefined_type_t_in_spec — 2026-07-23
- Files:
  - `lib/semantic/fix_undefined_type_t_in_spec.ex`
  - `test/semantic/fix_undefined_type_t_in_spec_check_test.exs`
  - `test/semantic/fix_undefined_type_t_in_spec_fix_test.exs`
- Reason: dead in production — match string "type t/0 is undefined" never occurs (real Elixir msg is "type t/0 undefined", no "is"); fixing the typo would make it match "type t/0 undefined" which accepted no_bare_names_in_spec already handles, and this rule sorts first (F<N, both prio 500) so Enum.find first-wins would hijack/regress that rule for bare-name-`t` specs — deconflicting needs a shared lib/semantic.ex change.

## fix_undefined_underscored_binding — 2026-07-23
- Files:
  - `lib/semantic/fix_undefined_underscored_binding.ex`
  - `test/semantic/fix_undefined_underscored_binding_check_test.exs`
  - `test/semantic/fix_undefined_underscored_binding_fix_test.exs`
- Reason: dead in production — accepted FixCaseBranchAssignmentScope.match? claims every `undefined variable "name"` error and sorts first (C<U, both priority 500), so Enum.find (first-wins, no fall-through) routes this diagnostic to it (empirically confirmed) and this rule never fires; its no-op fix leaves the underscore bug unfixed. Deconflicting needs a shared lib/semantic.ex change.

## fix_undefined_variable_in_equality — 2026-07-23
- Files:
  - `lib/semantic/fix_undefined_variable_in_equality.ex`
  - `test/semantic/fix_undefined_variable_in_equality_check_test.exs`
  - `test/semantic/fix_undefined_variable_in_equality_fix_test.exs`
- Reason: dead in production — FixCaseBranchAssignmentScope.match? claims every `undefined variable "name"` and sorts first (C<U, both priority 500), so Enum.find (first-wins) routes the diagnostic to it and this rule never fires; its no-op fix leaves the equality bug unfixed. Deconflicting needs a shared lib/semantic.ex change.

## fix_undefined_variable_in_helper_scope — 2026-07-23
- Files:
  - `lib/semantic/fix_undefined_variable_in_helper_scope.ex`
  - `test/semantic/fix_undefined_variable_in_helper_scope_check_test.exs`
  - `test/semantic/fix_undefined_variable_in_helper_scope_fix_test.exs`
- Reason: dead in production — FixCaseBranchAssignmentScope.match? claims every `undefined variable "name"` and sorts first (C<U, both priority 500), so Enum.find (first-wins, no fall-through) routes the diagnostic to it (empirically confirmed: winner = FixCaseBranchAssignmentScope) and this rule never fires. Deconflicting needs a shared lib/semantic.ex change.

## fix_undefined_variable_in_with_else — 2026-07-23
- Files:
  - `lib/semantic/fix_undefined_variable_in_with_else.ex`
  - `test/semantic/fix_undefined_variable_in_with_else_check_test.exs`
  - `test/semantic/fix_undefined_variable_in_with_else_fix_test.exs`
- Reason: dead in production — FixCaseBranchAssignmentScope.match? claims every `undefined variable "name"` error and sorts first (C<U, both priority 500), so Enum.find (first-wins) routes the diagnostic to it (empirically confirmed: winner = FixCaseBranchAssignmentScope, whose fix no-ops on the with/else shape) and this rule never fires; deconflicting needs a shared lib/semantic.ex change.

## fix_underscored_fn_param_binding_for_body_use — 2026-07-23
- Files:
  - `lib/semantic/fix_underscored_fn_param_binding_for_body_use.ex`
  - `test/semantic/fix_underscored_fn_param_binding_for_body_use_check_test.exs`
  - `test/semantic/fix_underscored_fn_param_binding_for_body_use_fix_test.exs`
- Reason: dead in production — FixCaseBranchAssignmentScope.match? claims every `undefined variable "name"` error and sorts first (C<U, both priority 500), so Enum.find (first-wins, no fall-through) routes the diagnostic to it and its no-op fix leaves the underscored-fn-param bug unfixed; this rule never fires. Deconflicting needs a shared lib/semantic.ex change.

## fix_underscored_pattern_binding_for_body_use — 2026-07-23
- Files:
  - `lib/semantic/fix_underscored_pattern_binding_for_body_use.ex`
  - `test/semantic/fix_underscored_pattern_binding_for_body_use_check_test.exs`
  - `test/semantic/fix_underscored_pattern_binding_for_body_use_fix_test.exs`
- Reason: dead in production — FixCaseBranchAssignmentScope.match? claims every `undefined variable "name"` error and sorts first (C<U, both priority 500), so Enum.find (first-wins, no fall-through) routes the diagnostic to it (empirically confirmed: winner = FixCaseBranchAssignmentScope, Credence.Semantic.fix returns CHANGED? false) and this rule never fires. Deconflicting needs a shared lib/semantic.ex change.

## fix_unmatchable_tuple_destructure — 2026-07-23
- Files:
  - `lib/semantic/fix_unmatchable_tuple_destructure.ex`
  - `test/semantic/fix_unmatchable_tuple_destructure_check_test.exs`
  - `test/semantic/fix_unmatchable_tuple_destructure_fix_test.exs`
- Reason: hallucinated premise (integer-as-tuple destructure raises runtime MatchError, never emits "misplaced operator |/2") and the fix {var,_}=expr -> var=expr changes the answer on valid partial-destructures like {v,_}=Integer.parse(x); no safe core.

## no_agent_update_tuple_wrapper — 2026-07-23
- Files:
  - `lib/semantic/no_agent_update_tuple_wrapper.ex`
  - `test/semantic/no_agent_update_tuple_wrapper_check_test.exs`
  - `test/semantic/no_agent_update_tuple_wrapper_fix_test.exs`
- Reason: dead in production — keys on fabricated message "Agent.update callback should return new state, not {:ok, state}" that the Elixir compiler never emits (verified: 0 diagnostics), so semantic phase (compile_and_capture/with_diagnostics only) never routes a real diagnostic to match?; making it live needs a shared-file custom-analyzer change.

## no_atom_position_in_list_key_functions — 2026-07-23
- Files:
  - `lib/semantic/no_atom_position_in_list_key_functions.ex`
  - `test/semantic/no_atom_position_in_list_key_functions_check_test.exs`
  - `test/semantic/no_atom_position_in_list_key_functions_fix_test.exs`
- Reason: dead in production — match? keys on "redefining module" but the atom-position bug emits "incompatible types given to List.keytake/3" (verified), so the rule never fires on its target; and the fix diverges anyway (Enum.reject removes ALL matches / t.field map access vs keytake removing the FIRST via tuple position), so there is no safe same-answer core to re-aim it to.

## no_bare_function_def_syntax — 2026-07-23
- Files:
  - `lib/semantic/no_bare_function_def_syntax.ex`
  - `test/semantic/no_bare_function_def_syntax_check_test.exs`
  - `test/semantic/no_bare_function_def_syntax_fix_test.exs`
- Reason: broad match? claims every "undefined function X/N" error and sorts before UndefinedFunction (N<U, both priority 500), so Enum.find first-wins routes those diagnostics to this rule, whose fix no-ops on non-`def` lines — empirically starving UndefinedFunction's live local replacements (sorted->Enum.sort, len->length, max/min/sum, range->literal, reversed, infinity), a regression. match? can't see source so it can't be narrowed to bare-def lines; deconflicting needs a shared lib/semantic.ex fall-through change.

## no_bare_return_in_genserver_init — 2026-07-23
- Files:
  - `lib/semantic/no_bare_return_in_genserver_init.ex`
  - `test/semantic/no_bare_return_in_genserver_init_check_test.exs`
  - `test/semantic/no_bare_return_in_genserver_init_fix_test.exs`
- Reason: dead in production — keys on fabricated message "init/1 must return {:ok, state}" that the Elixir compiler never emits (verified: bare init/1 return yields 0 diagnostics; it's a runtime {:bad_return_value} error, not a compile warning), so the semantic phase never routes a real diagnostic to match?; making it live needs a shared-file custom-analyzer change.

## no_bare_return_keyword — 2026-07-23
- Files:
  - `lib/semantic/no_bare_return_keyword.ex`
  - `test/semantic/no_bare_return_keyword_check_test.exs`
  - `test/semantic/no_bare_return_keyword_fix_test.exs`
- Reason: dead in production — fix_case_branch_assignment_scope's regex also claims `undefined variable "return"` and sorts first at equal priority 500 (Enum.find first-wins), no-ops on bare-return input, so this rule's fix never runs (verified: Credence.Semantic.fix leaves the return in place). Deconflicting needs a shared-file routing/priority change.

## no_capture_as_bitwise_and — 2026-07-23
- Files:
  - `lib/semantic/no_capture_as_bitwise_and.ex`
  - `test/semantic/no_capture_as_bitwise_and_check_test.exs`
  - `test/semantic/no_capture_as_bitwise_and_fix_test.exs`
- Reason: fix_pipe_capture rewrites the whole file and has_bare_capture? can't distinguish a bare &1 from a &1 inside a valid &(...), so a valid `list |> Enum.map(&(&1 + 1))` elsewhere in the file is mangled into `&(wq1 + 1)` (capture without argument = compile error), while the actually-flagged bare `foo(&1)` stays unfixed; valid_syntax? only parses so it hides this.

## no_compile_warn_undefined_module — 2026-07-23
- Files:
  - `lib/semantic/no_compile_warn_undefined_module.ex`
  - `test/semantic/no_compile_warn_undefined_module_check_test.exs`
  - `test/semantic/no_compile_warn_undefined_module_fix_test.exs`
- Reason: rule is live/safe but firing on real undefined-module warnings regresses 6 sibling rules' "resolves-elsewhere-via-alias left untouched" e2e tests (aliased-module warning is indistinguishable from its own target, so no narrowing saves it); deconflicting needs shared-file changes (those 6 test fixtures or pipeline routing) which are out of scope.

## no_cond_variable_assignment_in_inner_branch — 2026-07-23
- Files:
  - `lib/semantic/no_cond_variable_assignment_in_inner_branch.ex`
  - `test/semantic/no_cond_variable_assignment_in_inner_branch_check_test.exs`
  - `test/semantic/no_cond_variable_assignment_in_inner_branch_fix_test.exs`
- Reason: dead in production — FixCaseBranchAssignmentScope.match? claims every `undefined variable` diagnostic and sorts first (equal priority 500, name F<N), no-ops on if/else, pipeline stops so this rule's fix never runs (verified via real Credence.Semantic.fix: unchanged); also fix ignores position and over-applies file-wide, changing otherwise-valid code's return value. Deconflicting needs a shared-file routing/priority change.

## no_date_utc_today_with_arg — 2026-07-23
- Files:
  - `lib/semantic/no_date_utc_today_with_arg.ex`
  - `test/semantic/no_date_utc_today_with_arg_check_test.exs`
  - `test/semantic/no_date_utc_today_with_arg_fix_test.exs`
- Reason: check/fix mismatch — match? fires on the redundant-function-clause warning ("previous clause always matches"), which never corresponds to Date.utc_today(arg); fix no-ops on every real such diagnostic while claiming it from the rules that actually own it. Not narrowable; correct diagnostic would be the unrelated "undefined or private" message.

## no_define_to_string — 2026-07-23
- Files:
  - `lib/semantic/no_define_to_string.ex`
  - `test/semantic/no_define_to_string_check_test.exs`
  - `test/semantic/no_define_to_string_fix_test.exs`
- Reason: file-wide prewalk rename over-applies (renames Kernel.to_string in other modules → undefined function) and misses call forms (no-paren pipe, &to_string/1 capture) → silent behavior change; needs scope-aware rewrite, not narrowable.

## no_deprecated_not_in — 2026-07-23
- Files:
  - `lib/semantic/no_deprecated_not_in.ex`
  - `test/semantic/no_deprecated_not_in_check_test.exs`
  - `test/semantic/no_deprecated_not_in_fix_test.exs`
- Reason: line-level global regex rewrite changes semantics on flagged inputs — `not (a in b) in c` (nested/parenthesized `in`) mis-captures into the parens, and `not … in` inside string literals/comments on the flagged line is corrupted; not narrowable since semantic match? keys only on the message, so a correct fix needs a paren/string-aware parse using the column, not a regex shrink.

## no_discarded_unless_value — 2026-07-23
- Files:
  - `lib/semantic/no_discarded_unless_value.ex`
  - `test/semantic/no_discarded_unless_value_check_test.exs`
  - `test/semantic/no_discarded_unless_value_fix_test.exs`
- Reason: check/fix mismatch — Elixir emits no "unless expression result is unused" diagnostic (real msg is "code block contains unused literal"; discarded unless value warns not at all), so match? never fires; and the if/else rewrite changes behavior (returns the unless body instead of the always-returned trailing expression). Not narrowable.

## no_early_return_in_unless — 2026-07-23
- Files:
  - `lib/semantic/no_early_return_in_unless.ex`
  - `test/semantic/no_early_return_in_unless_check_test.exs`
  - `test/semantic/no_early_return_in_unless_fix_test.exs`
- Reason: duplicate of live NoBareReturnInUnless (identical "undefined function return/" + :error match, same unless/if early-return coverage); new rule adds nothing safe — its if/return fix is inverted (puts rest in do, value in else, returning the wrong branch for every if-early-return). Drop/fold requires touching the other rule, out of set scope.

## no_enum_sort_then_map_values — 2026-07-23
- Files:
  - `lib/semantic/no_enum_sort_then_map_values.ex`
  - `test/semantic/no_enum_sort_then_map_values_check_test.exs`
  - `test/semantic/no_enum_sort_then_map_values_fix_test.exs`
- Reason: check/fix mismatch — match? keys on the unrelated "operator '+'/2 is ignored" (unused-arithmetic) warning while fix rewrites sort_by→Map.values pipes, so the flagged diagnostic is never resolved and unrelated pipes may be corrupted; the intended target raises a runtime BadMapError, not a diagnostic, so no message-keyed semantic rule can match it. Not narrowable.

## no_ets_info_bare_size — 2026-07-23
- Files:
  - `lib/semantic/no_ets_info_bare_size.ex`
  - `test/semantic/no_ets_info_bare_size_check_test.exs`
  - `test/semantic/no_ets_info_bare_size_fix_test.exs`
- Reason: dead rule — at default priority 500 it's shadowed by FixCaseBranchAssignmentScope (also 500, sorts first, claims whole `undefined variable "name"` family and no-ops on ets.info sources), so `:ets.info(t, size)` is never fixed end-to-end; lowering to 450 would steal the common `size` variable diagnostic from that live rule and regress its case-branch-scope fix. Resolving needs a shared-file change (coordinate the two rules / phase fallthrough), out of set scope.

## no_exit_two_args — 2026-07-23
- Files:
  - `lib/semantic/no_exit_two_args.ex`
  - `test/semantic/no_exit_two_args_check_test.exs`
  - `test/semantic/no_exit_two_args_fix_test.exs`
- Reason: duplicate dispatch — live UndefinedFunction already matches "undefined function exit/2" and its @local_replacements is the home for exactly this Python-idiom rename ({"exit",2} => {:rename,"Process","exit"}, reusing its word-boundary-safe replacer); this standalone rule shadows it with an unsafe naive String.replace("exit(",…) that mangles Process.exit(/Foo.exit(/string-literal lines. Clean fold requires editing undefined_function.ex — out of set scope.

## no_function_in_module_attribute — 2026-07-23
- Files:
  - `lib/semantic/no_function_in_module_attribute.ex`
  - `test/semantic/no_function_in_module_attribute_check_test.exs`
  - `test/semantic/no_function_in_module_attribute_fix_test.exs`
- Reason: duplicate — identical match?/1 (same "cannot inject attribute" + "cannot escape #Function" diagnostic) as live Semantic.FixFunctionInModuleAttributeInlineUsages, which already fixes this safely; new rule also unsafely removes the @attr def while leaving bare @attr value refs dangling. Drop/fold needs the other set's file, out of scope.

## no_genserver_cast_with_raise — 2026-07-23
- Files:
  - `lib/semantic/no_genserver_cast_with_raise.ex`
  - `test/semantic/no_genserver_cast_with_raise_check_test.exs`
  - `test/semantic/no_genserver_cast_with_raise_fix_test.exs`
- Reason: check/fix mismatch — match?/1 keys on the "@impl true ... no behaviour was declared" warning (missing `use GenServer`), but the fix only rewrites handle_cast→handle_call and GenServer.cast→.call and never adds `use GenServer`/@behaviour, so the flagged diagnostic remains unresolved after the fix; the real target (a cast handler that raises) emits no compiler diagnostic, so no message-keyed semantic rule can key on it. Not narrowable.

## no_genserver_reply_in_handle_call — 2026-07-23
- Files:
  - `lib/semantic/no_genserver_reply_in_handle_call.ex`
  - `test/semantic/no_genserver_reply_in_handle_call_check_test.exs`
  - `test/semantic/no_genserver_reply_in_handle_call_fix_test.exs`
- Reason: dead rule — match? keys on a fabricated message ("send/2 used to reply from handle_call/3 …") the Elixir compiler never emits; send-in-handle_call is valid code (runtime caller-timeout bug, no compile diagnostic), so no message-keyed semantic rule can ever match it. Not narrowable; belongs to a pattern/AST rule (out of set scope).

## no_genserver_reply_in_handle_cast — 2026-07-23
- Files:
  - `lib/semantic/no_genserver_reply_in_handle_cast.ex`
  - `test/semantic/no_genserver_reply_in_handle_cast_check_test.exs`
  - `test/semantic/no_genserver_reply_in_handle_cast_fix_test.exs`
- Reason: dead rule — match?/1 keys on a fabricated diagnostic ("GenServer.reply/2 called inside handle_cast/2 …") the Elixir compiler never emits; GenServer.reply(bare_pid,_) in handle_cast is valid code (runtime FunctionClauseError, no compile diagnostic — verified Code.with_diagnostics returns 0), so no message-keyed semantic rule can ever match it. Same class as no_genserver_reply_in_handle_call (6374a54); belongs to a pattern/AST rule, out of set scope.

## no_genserver_tuple_piped_to_state_fn — 2026-07-23
- Files:
  - `lib/semantic/no_genserver_tuple_piped_to_state_fn.ex`
  - `test/semantic/no_genserver_tuple_piped_to_state_fn_check_test.exs`
  - `test/semantic/no_genserver_tuple_piped_to_state_fn_fix_test.exs`
- Reason: dead rule — match?/1 keys on a fabricated message ("GenServer reply tuple piped into helper function") the Elixir compiler never emits; piping a reply tuple into a helper is valid code (runtime BadMapError, Code.with_diagnostics returns only an unrelated @impl warning), so no message-keyed semantic rule can match it. Same class as 6374a54/1ab7d66/282488a; belongs to a pattern/AST rule, out of set scope.

## no_guard_before_validation — 2026-07-23
- Files:
  - `lib/semantic/no_guard_before_validation.ex`
  - `test/semantic/no_guard_before_validation_check_test.exs`
  - `test/semantic/no_guard_before_validation_fix_test.exs`
- Reason: dead rule — match?/1 keys on a fabricated message ("guard duplicates body validation") the Elixir compiler never emits; a comparison guard alongside a body `unless … raise` is valid code (Code.with_diagnostics returns 0 diagnostics), so no message-keyed semantic rule can ever match it. Same class as 6374a54/1ab7d66/282488a; the smell belongs to a pattern/AST rule, out of set scope.

## no_hallucinated_agent_update_and — 2026-07-23
- Files:
  - `lib/semantic/no_hallucinated_agent_update_and.ex`
  - `test/semantic/no_hallucinated_agent_update_and_check_test.exs`
  - `test/semantic/no_hallucinated_agent_update_and_fix_test.exs`
- Reason: duplicate of generic Credence.Semantic.UndefinedFunction — its match? already fires on "Agent.update_and/2 is undefined or private" (parse_qualified_ref → {"Agent","update_and",2}), so both rules claim the same diagnostic; the correct fold is a one-line @qualified_replacements entry {"Agent","update_and",2} => {:rename,"Agent","get_and_update"} in lib/semantic/undefined_function.ex, a shared-file change that is out of scope.

## no_hallucinated_base_hex_encode — 2026-07-23
- Files:
  - `lib/semantic/no_hallucinated_base_hex_encode.ex`
  - `test/semantic/no_hallucinated_base_hex_encode_check_test.exs`
  - `test/semantic/no_hallucinated_base_hex_encode_fix_test.exs`
- Reason: duplicate of Credence.Semantic.UndefinedFunction — its match? already fires on "Base.hex_encode/1 is undefined or private" (parse_qualified_ref → {"Base","hex_encode",1}), so both rules claim the same diagnostic; the correct fold is @qualified_replacements entries {"Base","hex_encode",2}=>{:rename,"Base","encode16"} and {"Base","hex_encode",0/1}=>{:rename_add_arg,"Base","encode16","case: :lower"} in lib/semantic/undefined_function.ex, a shared-file change out of scope.

## no_hallucinated_crypto_compare — 2026-07-23
- Files:
  - `lib/semantic/no_hallucinated_crypto_compare.ex`
  - `test/semantic/no_hallucinated_crypto_compare_check_test.exs`
  - `test/semantic/no_hallucinated_crypto_compare_fix_test.exs`
- Reason: duplicate of Credence.Semantic.UndefinedFunction — its match? already fires on ":crypto.compare/2 is undefined or private" (parse_qualified_ref → {"crypto","compare",2}), so both rules claim the same diagnostic; correct fold is a @qualified_replacements entry {"crypto","compare",2} => {:rename,"crypto","hash_equals"} in lib/semantic/undefined_function.ex, a shared-file change out of scope.

## no_hallucinated_crypto_hex — 2026-07-23
- Files:
  - `lib/semantic/no_hallucinated_crypto_hex.ex`
  - `test/semantic/no_hallucinated_crypto_hex_check_test.exs`
  - `test/semantic/no_hallucinated_crypto_hex_fix_test.exs`
- Reason: duplicate of Credence.Semantic.UndefinedFunction — its match? already fires on ":crypto.hex/1 is undefined or private" (parse_qualified_ref → {"crypto","hex",1}), so both rules claim the same diagnostic; correct fold is a @qualified_replacements entry {"crypto","hex",1} in lib/semantic/undefined_function.ex, a shared-file change out of scope.

## no_hallucinated_erlang_warn — 2026-07-23
- Files:
  - `lib/semantic/no_hallucinated_erlang_warn.ex`
  - `test/semantic/no_hallucinated_erlang_warn_check_test.exs`
  - `test/semantic/no_hallucinated_erlang_warn_fix_test.exs`
- Reason: duplicate of Credence.Semantic.UndefinedFunction — its match? already fires on ":erlang.warn/1 is undefined or private" (parse_qualified_ref → {"erlang","warn",1}), so both rules claim the same diagnostic; correct fold is a @qualified_replacements entry {"erlang","warn",1} in lib/semantic/undefined_function.ex, a shared-file change out of scope.

## no_hallucinated_fetch_part — 2026-07-23
- Files:
  - `lib/semantic/no_hallucinated_fetch_part.ex`
  - `test/semantic/no_hallucinated_fetch_part_check_test.exs`
  - `test/semantic/no_hallucinated_fetch_part_fix_test.exs`
- Reason: match? keys on the "init/1 implemented as defp" Plug warning but fix rewrites an unrelated Plug.Conn.fetch_part case and never touches init/1, so the flagged diagnostic is never resolved; re-keying to the "fetch_part/2 is undefined or private" message would duplicate Credence.Semantic.UndefinedFunction (a shared-file fold, out of scope).

## no_hallucinated_map_reduce — 2026-07-23
- Files:
  - `lib/semantic/no_hallucinated_map_reduce.ex`
  - `test/semantic/no_hallucinated_map_reduce_check_test.exs`
  - `test/semantic/no_hallucinated_map_reduce_fix_test.exs`
- Reason: duplicate of Credence.Semantic.UndefinedFunction — its match? already fires on "Map.reduce/3 is undefined or private" (parse_qualified_ref → {"Map","reduce",3}), so both rules claim the same diagnostic; correct fold is a @qualified_replacements entry in lib/semantic/undefined_function.ex, a shared-file change out of scope (and the Map.reduce→Enum.reduce callback restructuring isn't expressible via the existing rename machinery anyway).

## no_hallucinated_math_fn — 2026-07-23
- Files:
  - `lib/semantic/no_hallucinated_math_fn.ex`
  - `test/semantic/no_hallucinated_math_fn_check_test.exs`
  - `test/semantic/no_hallucinated_math_fn_fix_test.exs`
- Reason: duplicate of Credence.Semantic.UndefinedFunction — its match? already fires on ":math.min/2 is undefined or private" (parse_qualified_ref → {"math","min",2}), so both rules claim the same diagnostic; correct fold is @qualified_replacements entries {"math","min",2}/{"math","max",2} in lib/semantic/undefined_function.ex, a shared-file change out of scope.

## no_hallucinated_math_round — 2026-07-23
- Files:
  - `lib/semantic/no_hallucinated_math_round.ex`
  - `test/semantic/no_hallucinated_math_round_check_test.exs`
  - `test/semantic/no_hallucinated_math_round_fix_test.exs`
- Reason: fabricated premise — :math.round(x) parses as a normal call and errors ":math.round/1 is undefined or private" (verified), NOT "misplaced operator ::/2"; the rule keys on the latter so it never fires on its target, and the real diagnostic is already owned by Credence.Semantic.UndefinedFunction (parse_qualified_ref → {"math","round",1}); correct fold is a {"math","round",1} => {:drop_module,"round"} entry in lib/semantic/undefined_function.ex, a shared-file change out of scope.

## no_hallucinated_math_round2 — 2026-07-23
- Files:
  - `lib/semantic/no_hallucinated_math_round2.ex`
  - `test/semantic/no_hallucinated_math_round2_check_test.exs`
  - `test/semantic/no_hallucinated_math_round2_fix_test.exs`
- Reason: duplicate of Credence.Semantic.UndefinedFunction — its match? already fires on ":math.round/1 is undefined or private" (parse_qualified_ref → {"math","round",1}), so both rules claim the same diagnostic; correct fold is a {"math","round",1} => {:drop_module,"round"} entry in lib/semantic/undefined_function.ex, a shared-file change out of scope.

