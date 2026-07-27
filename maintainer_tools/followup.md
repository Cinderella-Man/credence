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

## no_hallucinated_naive_datetime_to_unix — 2026-07-23
- Files:
  - `lib/semantic/no_hallucinated_naive_datetime_to_unix.ex`
  - `test/semantic/no_hallucinated_naive_datetime_to_unix_check_test.exs`
  - `test/semantic/no_hallucinated_naive_datetime_to_unix_fix_test.exs`
- Reason: fabricated premise — NaiveDateTime has no to_unix at any arity, so stripping the arg yields NaiveDateTime.to_unix/1 which is itself undefined; the fix doesn't resolve the diagnostic and there's no safe narrow core (real conversion needs a timezone assumption / NaiveDateTime.diff).

## no_hallucinated_persistent_term_fn — 2026-07-23
- Files:
  - `lib/semantic/no_hallucinated_persistent_term_fn.ex`
  - `test/semantic/no_hallucinated_persistent_term_fn_check_test.exs`
  - `test/semantic/no_hallucinated_persistent_term_fn_fix_test.exs`
- Reason: fabricated premise — rule keys on "clauses with the same name and arity ... should be grouped together" (function-clause grouping), which is never the diagnostic its target :persistent_term.get_keys() produces (":persistent_term.get_keys/0 is undefined or private"), so it never fires on its own target; and that real diagnostic is already owned by Credence.Semantic.UndefinedFunction (match? on "is undefined or private" + parse_qualified_ref -> {"persistent_term","get_keys",0}). Correct fold is a @qualified_replacements entry in lib/semantic/undefined_function.ex (shared-file, out of scope), and the get_keys->get callback restructuring (fn key -> fn {key,_value}) isn't expressible via the rename machinery anyway.

## no_hallucinated_queue_empty — 2026-07-23
- Files:
  - `lib/semantic/no_hallucinated_queue_empty.ex`
  - `test/semantic/no_hallucinated_queue_empty_check_test.exs`
  - `test/semantic/no_hallucinated_queue_empty_fix_test.exs`
- Reason: duplicate of Credence.Semantic.UndefinedFunction — its match? already fires on ":queue.empty/0 is undefined or private" (parse_qualified_ref → {"queue","empty",0}), so both rules claim the same diagnostic; correct fold is a {"queue","empty",0} => {:rename,"queue","new"} entry in lib/semantic/undefined_function.ex, a shared-file change out of scope.

## no_hallucinated_stream_data_string — 2026-07-23
- Files:
  - `lib/semantic/no_hallucinated_stream_data_string.ex`
  - `test/semantic/no_hallucinated_stream_data_string_check_test.exs`
  - `test/semantic/no_hallucinated_stream_data_string_fix_test.exs`
- Reason: duplicate of Credence.Semantic.UndefinedFunction — its match? already fires on both ":warning" diagnostics ("StreamData.alpha_string/0 is undefined or private", "StreamData.string_of_length/2 is undefined or private") via parse_qualified_ref, so both rules claim the same diagnostic; correct fold is into lib/semantic/undefined_function.ex (alpha_string -> {:rename_add_arg,"StreamData","string",":alphanumeric"}; string_of_length needs new range->keyword machinery there), a shared-file change out of scope.

## no_hallucinated_struct — 2026-07-23
- Files:
  - `lib/semantic/no_hallucinated_struct.ex`
  - `test/semantic/no_hallucinated_struct_check_test.exs`
  - `test/semantic/no_hallucinated_struct_fix_test.exs`
- Reason: duplicate matcher — match? is byte-identical to Credence.Semantic.FixCyclicStructReference ("__struct__/1 is undefined", :error), same priority 500, and Semantic.find_matching_rule/Enum.find returns FixCyclicStructReference first (F<N), so NoHallucinatedStruct.fix never runs in production (confirmed empirically). Correct fold is a shared-file change into fix_cyclic_struct_reference.ex (add the undefined-anywhere→tuple fallback), out of scope. (Also the fix over-rewrites: it converts EVERY struct literal not locally defstruct'd — incl. valid stdlib structs like %DateTime{}/%URI{} anywhere in the file — into tuples, ignoring the diagnostic's named module.)

## no_hallucinated_struct_field_in_pattern — 2026-07-23
- Files:
  - `lib/semantic/no_hallucinated_struct_field_in_pattern.ex`
  - `test/semantic/no_hallucinated_struct_field_in_pattern_check_test.exs`
  - `test/semantic/no_hallucinated_struct_field_in_pattern_fix_test.exs`
- Reason: fabricated premise — real hallucinated-struct-field diagnostic is "unknown key :size for struct X", but match? keys on the runtime KeyError message "key :size not found" (confirmed via Exception.message(%KeyError{key: :size})), so it never fires on its documented target; and the fix hardcodes `var = File.stat!(path).size`, unsafe/nonsensical for any struct+field other than Plug.Upload/size — a removed pattern binding's value can't be recovered in general, so there is no narrow safe core.

## no_hardcoded_genserver_name_in_api — 2026-07-23
- Files:
  - `lib/semantic/no_hardcoded_genserver_name_in_api.ex`
  - `test/semantic/no_hardcoded_genserver_name_in_api_check_test.exs`
  - `test/semantic/no_hardcoded_genserver_name_in_api_fix_test.exs`
- Reason: fabricated premise — match? keys on the unrelated ":catch in case" compile diagnostic while fix rewrites GenServer.call(__MODULE__)/ETS-atom code, so check and fix never agree and the fix never resolves the flagged diagnostic; fix is also hardcoded to :feature_flags/:feature_flags_history atoms and fabricated state.table_name/hist_name fields, unsafe for any real module. No narrow safe core.

## no_if_assignment_as_statement — 2026-07-23
- Files:
  - `lib/semantic/no_if_assignment_as_statement.ex`
  - `test/semantic/no_if_assignment_as_statement_check_test.exs`
  - `test/semantic/no_if_assignment_as_statement_fix_test.exs`
- Reason: duplicate matcher — shadowed by Credence.Semantic.FixCaseBranchAssignmentScope, whose match?/1 claims EVERY `undefined variable "x"` diagnostic (never reads source) and sorts alphabetically before this rule at equal priority 500, so find_matching_rule (Enum.find) returns it first; it no-ops on the if-pattern (no case) and there is no fallthrough, so Credence.Semantic.fix leaves the code unchanged and NoIfAssignmentAsStatement.match?/fix never run in production (confirmed empirically: FIRST_MATCH=FixCaseBranchAssignmentScope, PIPELINE_CHANGED=false). Correct fold is into fix_case_branch_assignment_scope.ex (extend it to also hoist the two-branch if-assignment shape), a shared-file change out of scope.

## no_import_local_function_conflict — 2026-07-23
- Files:
  - `lib/semantic/no_import_local_function_conflict.ex`
  - `test/semantic/no_import_local_function_conflict_check_test.exs`
  - `test/semantic/no_import_local_function_conflict_fix_test.exs`
- Reason: catch-all shadows accepted PreferKernelMaxOverLocal — its regex matches "imported Kernel.max/2 conflicts with local function" (func=max != to_string), and at priority 400 (< the sibling's 500) it wins find_matching_rule (Enum.find over {priority,module}-sorted rules), applying its blunt generate_max rename instead of that dedicated rule's Kernel.max requalification (confirmed empirically). Narrowing/fold touches other rule files, out of scope.

## no_in_guard_with_variable_rhs — 2026-07-23
- Files:
  - `lib/semantic/no_in_guard_with_variable_rhs.ex`
  - `test/semantic/no_in_guard_with_variable_rhs_check_test.exs`
  - `test/semantic/no_in_guard_with_variable_rhs_fix_test.exs`
- Reason: fix is heuristic intent-reconstruction overfit to the demo — on an in-only guard (no `or`) it emits `[first|rest] -> true` matching any non-empty list unconditionally (wrong answer for `[?a,?b]`); it hardcodes Enum.member? ignoring the real body and duplicates the body into `[?| | _] -> body` leaving pattern vars unbound (compile error / wrong return type); and it no-ops on function-head guards, so match? fires without a resolving fix. Not narrowable via match? (diagnostic message carries none of the distinguishing shape info); no generalizable safe core.

## no_list_keystore_three_args — 2026-07-23
- Files:
  - `lib/semantic/no_list_keystore_three_args.ex`
  - `test/semantic/no_list_keystore_three_args_check_test.exs`
  - `test/semantic/no_list_keystore_three_args_fix_test.exs`
- Reason: fix inserts 0 in the wrong slot (keystore signature is (list,key,position,new_tuple)) so shipped output raises `no function clause matching in List.keystore/4` at runtime; even re-aimed to the correct slot it speculatively invents position=0 unconditionally, and the provably-safe core (new_tuple first element == key) can't be isolated since match? only sees the diagnostic — firing on all keystore/3 turns a compile error into a silent wrong-position logic bug and narrowing only the fix breaks check/fix agreement.

## no_map_get_on_keyword_list_opts — 2026-07-23
- Files:
  - `lib/semantic/no_map_get_on_keyword_list_opts.ex`
  - `test/semantic/no_map_get_on_keyword_list_opts_check_test.exs`
  - `test/semantic/no_map_get_on_keyword_list_opts_fix_test.exs`
- Reason: match? keys on a phantom message ("Map.get/2 called on keyword list opts") the compiler never emits, so the rule never fires; the real diagnostic ("incompatible types given to Map.get/2") is identical for string/integer/atom first-args where Keyword.get raises, and the fix blanket-rewrites every Map.get in the file (position-ignorant), breaking legitimate Map.get(real_map, k) calls — not narrowable to a safe core in-scope.

## no_map_update_zero_default_with_subtraction — 2026-07-23
- Files:
  - `lib/semantic/no_map_update_zero_default_with_subtraction.ex`
  - `test/semantic/no_map_update_zero_default_with_subtraction_check_test.exs`
  - `test/semantic/no_map_update_zero_default_with_subtraction_fix_test.exs`
- Reason: fix rewrites the callback to `existing + amount` (unconditionally additive), so every debit on an existing key becomes `existing + amount` instead of `existing - amount` — verified {500 vs 1500} — a real answer change, not preservation; the moduledoc premise is also false (Map.update inserts the default verbatim on key-absent and never calls the callback, so the described `0 - amount` bug doesn't exist), and match? fires on a phantom message the compiler never emits. Not narrowable: match? carries no shape info and even a corrected callback still changes the original's key-absent result.

## no_mapset_member_in_guard — 2026-07-23
- Files:
  - `lib/semantic/no_mapset_member_in_guard.ex`
  - `test/semantic/no_mapset_member_in_guard_check_test.exs`
  - `test/semantic/no_mapset_member_in_guard_fix_test.exs`
- Reason: fix reuses the guarded clause head and discards the fallback clause's head/patterns, so it emits undefined-variable/broken output on different param names, makes later clauses unreachable (silently wrong answer) with ≥3 clauses, and FunctionClauseErrors when the guarded head is narrower; the diagnostic-only check carries no shape info to narrow safe from unsafe, and narrowing only the fix breaks check/fix agreement.

## no_pin_in_after_clause — 2026-07-23
- Files:
  - `lib/semantic/no_pin_in_after_clause.ex`
  - `test/semantic/no_pin_in_after_clause_check_test.exs`
  - `test/semantic/no_pin_in_after_clause_fix_test.exs`
- Reason: duplicate of already-accepted fix_pin_in_ets_match_spec (identical match? on "misplaced operator ^" prefix; that rule already strips misplaced pins in any non-match context incl. after clauses, with a more precise line+column+var-name match and a should_report?/2 hook this candidate lacks).

## no_pipe_into_in_expression — 2026-07-23
- Files:
  - `lib/semantic/no_pipe_into_in_expression.ex`
  - `test/semantic/no_pipe_into_in_expression_check_test.exs`
  - `test/semantic/no_pipe_into_in_expression_fix_test.exs`
- Reason: fix wraps from line-start not the `in` left-operand boundary — silently changes semantics on valid code (`is_admin = user |> get_role() in roles` → assigns role not boolean) and breaks syntax on `def/when/do:/assert`; needs precedence-aware AST parsing, not a line regex; no safe narrow core.

## no_plug_before_dependency_definition — 2026-07-23
- Files:
  - `lib/semantic/no_plug_before_dependency_definition.ex`
  - `test/semantic/no_plug_before_dependency_definition_check_test.exs`
  - `test/semantic/no_plug_before_dependency_definition_fix_test.exs`
- Reason: check/fix disagree — match? fires on the syntax error "atom cannot be followed by an alias" (from a stray colon, e.g. plug(:Foo.Bar)), whose only correct fix is removing that colon, but fix/2 instead reorders module definitions and never removes the colon, so the flagged diagnostic is never resolved (verified: reorder output still contains plug(:Foo.Bar)); the moduledoc describes an unrelated init/1-undefined compile error match? never matches; tests pass only because the fix inputs use colon-free plug calls that would never emit the matched diagnostic. No safe core of the reorder behavior exists.

## no_plug_upload_size_field — 2026-07-23
- Files:
  - `lib/semantic/no_plug_upload_size_field.ex`
  - `test/semantic/no_plug_upload_size_field_check_test.exs`
  - `test/semantic/no_plug_upload_size_field_fix_test.exs`
- Reason: unsafe — fix hardcodes a `path` var (undefined-var compile error when absent), leaves expression-use of `size` undefined, mangles multiline patterns and changes tuple arity, and inserts File.stat! at module level; needs ground-up Sourceror rewrite, not narrowing.

## no_private_fn_called_from_macro_quote — 2026-07-23
- Files:
  - `lib/semantic/no_private_fn_called_from_macro_quote.ex`
  - `test/semantic/no_private_fn_called_from_macro_quote_check_test.exs`
  - `test/semantic/no_private_fn_called_from_macro_quote_fix_test.exs`
- Reason: fix premise is false — promoting defp→def does not make the quote-called helper resolve in the idiomatic `require M`/`M.macro` expansion (verified: undefined function check_order/1); it only helps `import M` callers and is a public-API change, while match?/to_issue claim EVERY "function/N is unused" warning (dead code included) and fix no-ops all non-quote cases (no should_report?/2), monopolizing those diagnostics via first-match. Correct remediation (qualify the call in the quote) is a redesign, not a narrowing.

## no_private_fn_in_timer_mfa — 2026-07-23
- Files:
  - `lib/semantic/no_private_fn_in_timer_mfa.ex`
  - `test/semantic/no_private_fn_in_timer_mfa_check_test.exs`
  - `test/semantic/no_private_fn_in_timer_mfa_fix_test.exs`
- Reason: same family as already-rejected no_private_fn_called_from_macro_quote — match? claims EVERY "function/N is unused" warning (genuine dead code included) with no should_report?/2, and the defp→def promotion fix over-reaches on both dimensions: referenced_via_timer_mfa? matches the target atom module-agnostically (PROBE A: MFA points at OtherMod, yet the local genuinely-dead do_cleanup/0 is made public) and find_defp_lines matches name-only arity-agnostically (PROBE B: only /1 flagged, but the unrelated private do_cleanup/2 is also promoted). Making both detections precise (verify MFA module == __MODULE__/self, match the flagged arity from source) plus adding should_report?/2 is a ground-up redesign, not a narrowing; and defp→def is itself a public-API change the maintainer flagged when rejecting the sibling rule.

## no_private_named_ets_readable_externally — 2026-07-23
- Files:
  - `lib/semantic/no_private_named_ets_readable_externally.ex`
  - `test/semantic/no_private_named_ets_readable_externally_check_test.exs`
  - `test/semantic/no_private_named_ets_readable_externally_fix_test.exs`
- Reason: check/fix disagree — match? fires on the general "incompatible types in binary construction" type warning (from String.to_atom(to_string(name))::binary), but the fix only changes :ets.new :private→:protected, which is orthogonal: verified the identical warning persists after the change, so the flagged diagnostic is never resolved (and :private→:protected is itself a runtime access-control change). The rule also monopolizes an unrelated general diagnostic via first-match; correct remediation (fix the binary construction) is a redesign, not a narrowing.

## no_process_send_after_infinity — 2026-07-23
- Files:
  - `lib/semantic/no_process_send_after_infinity.ex`
  - `test/semantic/no_process_send_after_infinity_check_test.exs`
  - `test/semantic/no_process_send_after_infinity_fix_test.exs`
- Reason: check/fix disagree — match? fires on the unrelated "multiple clauses and also declares default values" warning (whose correct fix is a header default), but fix/2 rewrites Process.send_after(...,:infinity) calls and returns such warning-producing code unchanged, so the flagged diagnostic is never resolved; meanwhile the fix's real target (send_after with :infinity) emits zero compile diagnostics (verified), so match? can never legitimately fire on it. Matched diagnostic and fix domain are disjoint — no safe narrow core.

## no_process_send_after_literal_infinity — 2026-07-23
- Files:
  - `lib/semantic/no_process_send_after_literal_infinity.ex`
  - `test/semantic/no_process_send_after_literal_infinity_check_test.exs`
  - `test/semantic/no_process_send_after_literal_infinity_fix_test.exs`
- Reason: check/fix disjoint — match? fires on the unrelated "variable X in code block has no effect as it is never returned" dead-variable warning (correct fix: remove var or bind to _), but fix/2 rewrites Process.send_after(...,variable) calls, which emit zero compile diagnostics (verified). The flagged diagnostic is never resolved and the fix's real target can never legitimately trigger match?. Same disjoint-domain defect already rejected for sibling no_process_send_after_infinity (2217cb1); no safe narrow core.

## no_process_send_after_with_variable_infinity — 2026-07-23
- Files:
  - `lib/semantic/no_process_send_after_with_variable_infinity.ex`
  - `test/semantic/no_process_send_after_with_variable_infinity_check_test.exs`
  - `test/semantic/no_process_send_after_with_variable_infinity_fix_test.exs`
- Reason: check/fix disjoint (same family as rejected 2217cb1/e88a273) — match? fires on the unrelated "invalid args for &" capture CompileError (correct fix: fix the & capture syntax), but fix/2 rewrites Process.send_after(...,variable) calls, which emit zero compile diagnostics (verified); so the flagged error is never resolved and the fix's real target can never legitimately trigger match?. match? also monopolizes every genuine &-capture error via first-match (no should_report?/2). A semantic rule needs a diagnostic to hook onto and the target produces none — no safe narrow core.

## no_process_send_two_args — 2026-07-23
- Files:
  - `lib/semantic/no_process_send_two_args.ex`
  - `test/semantic/no_process_send_two_args_check_test.exs`
  - `test/semantic/no_process_send_two_args_fix_test.exs`
- Reason: check/fix disjoint (match? claims unrelated "expected a map or struct" type warning via first-match while fix rewrites Process.send/2→send/2; flagged diagnostic never resolved) — same family as rejected 2217cb1/e88a273; the genuine "Process.send/2 is undefined or private" diagnostic is already claimed by the general UndefinedFunction rule, whose @qualified_replacements is the correct home ({"Process","send",2}=>{:drop_module,"send"}) — a shared-file change out of scope. No safe narrow core within the set.

## no_process_whereis_with_pid_arg — 2026-07-23
- Files:
  - `lib/semantic/no_process_whereis_with_pid_arg.ex`
  - `test/semantic/no_process_whereis_with_pid_arg_check_test.exs`
  - `test/semantic/no_process_whereis_with_pid_arg_fix_test.exs`
- Reason: check/fix disjoint — match? fires only on the generic "cannot compile module (errors have been logged)" wrapper, but the target `case Process.whereis(self())` guard compiles fine (verified) and emits zero compile diagnostics, so match? can never legitimately fire on it; the rule only triggers on unrelated compile failures where the fix (stripping the guard) never resolves the flagged diagnostic. Same family defect as rejected 2217cb1/e88a273/c35d48e/8374476/1cc8203; no safe narrow core.

## no_raise_in_handle_call — 2026-07-23
- Files:
  - `lib/semantic/no_raise_in_handle_call.ex`
  - `test/semantic/no_raise_in_handle_call_check_test.exs`
  - `test/semantic/no_raise_in_handle_call_fix_test.exs`
- Reason: fabricated diagnostic — match? fires only on the invented message "raise in handle_call — use {:reply, {:error, msg}, state} instead" which the Elixir compiler never emits (verified: raise in handle_call compiles cleanly, only unused-var + missing-init/1 diagnostics appear); rule is dead in production, no real diagnostic to hook onto, no safe narrow core. Same family as rejected disjoint/fabricated-diagnostic rules.

## no_raw_send_in_genserver_handle_call — 2026-07-23
- Files:
  - `lib/semantic/no_raw_send_in_genserver_handle_call.ex`
  - `test/semantic/no_raw_send_in_genserver_handle_call_check_test.exs`
  - `test/semantic/no_raw_send_in_genserver_handle_call_fix_test.exs`
- Reason: fabricated diagnostic — match? requires exact-string equality with the invented message "send/2 spawned from handle_call/3 — use GenServer.reply/2 instead", which the Elixir compiler never emits (verified: raw send/2 inside spawn in handle_call/3 compiles cleanly, emitting only the unrelated init/1 GenServer behaviour diagnostic). Semantic diagnostics come from Code.with_diagnostics, so the rule can never fire in production; the target shape produces zero compile diagnostics and there is no real diagnostic to hook onto — no safe narrow core. Same family as rejected e30768f/6910899/8374476.

## no_remote_function_in_guard — 2026-07-23
- Files:
  - `lib/semantic/no_remote_function_in_guard.ex`
  - `test/semantic/no_remote_function_in_guard_check_test.exs`
  - `test/semantic/no_remote_function_in_guard_fix_test.exs`
- Reason: fix is not behaviour-preserving — pop_fallback/find_wildcard_body treat the first no-guard clause / first `_` clause as a catch-all and splice its body into the generated `else`, silently dropping specific-pattern clauses and skipping intervening reachable ones (verified: `loop(a,b) when <remote>` + `loop(0,b)` + `loop(a,b)` merges the literal-pattern `loop(0,b)` and returns `:zero` for every non-zero `a`, leaving an unreachable clause; `pid when Map.has_key?(m,pid)` + `{:special,x}` + `_` makes `{:special,x}` unreachable, returning `:c` where the original returns `{:special_b,y}`). Same defect recurs on the compound-`and` path, and the merged head reuses the guarded clause's params while the `else` body keeps the fallback's, so mismatched param names produce unbound vars. Safe core would require rewriting fallback/wildcard selection across the def-merge, case-merge and compound-and paths to demand a genuine adjacent catch-all with identical bindings — a substantive rewrite, not a narrow carve-out.

## no_return_fn_in_conditional — 2026-07-23
- Files:
  - `lib/semantic/no_return_fn_in_conditional.ex`
  - `test/semantic/no_return_fn_in_conditional_check_test.exs`
  - `test/semantic/no_return_fn_in_conditional_fix_test.exs`
- Reason: duplicate of the live no_bare_return_in_unless — byte-identical match?/@match_msg ("undefined function return/", severity :error); Semantic.find_matching_rule uses Enum.find over rules sorted by {priority, module} and both are priority 500, so NoBareReturnInUnless (alphabetically first) always wins and this rule's fix/2 is unreachable in production (verified end-to-end: the incumbent handles the chained unless/return input). Making it reachable needs a shared-file change (fold the guard-chain restructuring into no_bare_return_in_unless, or add dispatch/priority in lib/semantic.ex) — out of scope. Separately, its fix leaves any unless/return guard not directly adjacent to the final expression in place, so the output still contains return/1 and still fails to compile.

## no_send_self_in_task — 2026-07-23
- Files:
  - `lib/semantic/no_send_self_in_task.ex`
  - `test/semantic/no_send_self_in_task_check_test.exs`
  - `test/semantic/no_send_self_in_task_fix_test.exs`
- Reason: fabricated diagnostic — Code.with_diagnostics emits nothing for send(self()) in a Task callback, so match?/1 is never true and the rule is dead in production; and the fix is unsafe anyway (inline `def f, do: Task.async(...)` yields module-level `parent = self()` + "undefined variable parent"; shadows an existing `parent` binding; rewrites every self() in the fn, not just the send target).

## no_send_to_from_in_handle_call — 2026-07-23
- Files:
  - `lib/semantic/no_send_to_from_in_handle_call.ex`
  - `test/semantic/no_send_to_from_in_handle_call_check_test.exs`
  - `test/semantic/no_send_to_from_in_handle_call_fix_test.exs`
- Reason: fabricated diagnostic — Code.with_diagnostics emits nothing for send(from, msg) in handle_call (verified: [] on Elixir 1.20.2), so match?/1 is never true and the rule is dead in production; and the fix is unsafe anyway (it keys purely on the variable name `from`, rewriting plain `def notify(from, msg), do: send(from, msg)` in a non-GenServer module into GenServer.reply/2, and Macro.to_string on the message arg silently drops comments inside it). Making it fire needs a new diagnostic source outside the set.

## no_shadowed_function_redefinition — 2026-07-23
- Files:
  - `lib/semantic/no_shadowed_function_redefinition.ex`
  - `test/semantic/no_shadowed_function_redefinition_check_test.exs`
  - `test/semantic/no_shadowed_function_redefinition_fix_test.exs`
- Reason: fabricated diagnostic + backwards fix — the real Elixir 1.20.2 message for a shadowed def/defp is "this clause for process/1 cannot match because a previous clause at line 2 always matches" (verified via Code.with_diagnostics for def, defp and arity-2), so match?/1's prefix "this clause cannot match because a previous clause at line " is never true and the rule is dead for its stated target; the only real message that does satisfy match?/1 is the case/cond form (no "for f/a"), where no def/defp sits on the target line and fix/2 is a guaranteed no-op, so check and fix disagree; and even if match?/1 were repaired, the fix removes the EARLIER (live) clause — in Elixir the first clause wins — changing the answer on every input (verified: Bef.process(21) == {:draft, 21} vs Aft.process(21) == {:ok, 42}), while the safe direction (delete the later dead clause) is already live as Pattern.RemoveUnreachableClausesAfterCatchall / Pattern.NoDuplicateFunctionClauses.

## no_split_function_definition — 2026-07-23
- Files:
  - `lib/semantic/no_split_function_definition.ex`
  - `test/semantic/no_split_function_definition_check_test.exs`
  - `test/semantic/no_split_function_definition_fix_test.exs`
- Reason: fabricated diagnostic ("has multiple clauses and they are not adjacent" is never emitted; real Elixir 1.20.2 message is "clauses with the same name and arity (number of arguments) should be grouped together, \"def handle_call/3\" was previously defined (file:3)") so match?/1 is never true and the rule is dead; and repairing it would only duplicate the live, better-guarded Pattern.NoNonGroupedClauses (Credence.Pattern.NonGroupedClauses), which already regroups these exact inputs while skipping strays preceded by @impl/@doc and unsafe-to-move bodies — guards this semantic version lacks, and Semantic runs before Pattern so it would preempt the safer rule.

## no_stream_data_constant_with_range — 2026-07-23
- Files:
  - `lib/semantic/no_stream_data_constant_with_range.ex`
  - `test/semantic/no_stream_data_constant_with_range_check_test.exs`
  - `test/semantic/no_stream_data_constant_with_range_fix_test.exs`
- Reason: fabricated diagnostic — `StreamData.constant(?a..?z)` emits no diagnostic at all (verified: Code.with_diagnostics returns [] on Elixir 1.20.2, since `constant(a) :: t(a) when a: var` accepts any term), so the fix path is dead for its stated target; the only real message satisfying match?/1 is the *different* bug `StreamData.integer({min,max})` ("incompatible types given to StreamData.integer/1 … but expected one of: %Range{}", verified — and note the test's @real_message is that one, not a constant/1 message), where no `StreamData.constant` call exists and fix/2 is a guaranteed no-op, so check and fix disagree; and even if it fired, the prewalk rewrites EVERY one-arg `StreamData.constant` regardless of the argument (verified: `StreamData.constant(:foo)` → `StreamData.member_of(:foo)`, which raises on a non-enumerable, and `constant([1,2,3])` → `member_of([1,2,3])`, which generates 1|2|3 instead of the constant list) — making it fire needs a new diagnostic source outside the set.

## no_undefined_guard_equality_in_case — 2026-07-24
- Files:
  - `lib/semantic/no_undefined_guard_equality_in_case.ex`
  - `test/semantic/no_undefined_guard_equality_in_case_check_test.exs`
  - `test/semantic/no_undefined_guard_equality_in_case_fix_test.exs`
- Reason: check and fix disagree — match?/1 only fires on the `:ets:info` "syntax error before: info" diagnostic, which the guard-equality regex rewrite never resolves (verified: fixed source still fails to parse), while valid `x when x == :atom` emits no diagnostic at all so no safe semantic hook exists; the unanchored global regex also breaks working code (`x when x == :ok and is_atom(x)` -> `:ok and is_atom(x)`, "and is not allowed in patterns"; `undefined when undefined == :undefined -> {:got, undefined}` -> unbound variable, cannot compile) and rewrites string literals/comments (`s = "x when x == :ok"` -> `s = ":ok"`).

## no_undefined_options_in_plug_router_block — 2026-07-24
- Files:
  - `lib/semantic/no_undefined_options_in_plug_router_block.ex`
  - `test/semantic/no_undefined_options_in_plug_router_block_check_test.exs`
  - `test/semantic/no_undefined_options_in_plug_router_block_fix_test.exs`
- Reason: dead in production — FixCaseBranchAssignmentScope (same priority 500, sorts first) already claims every `undefined variable "options"` diagnostic and Semantic.find_matching_rule takes only the first match, so this rule never fires; raising its priority would instead steal those diagnostics and silently break the accepted rule (fallthrough would need a lib/semantic.ex change, out of scope), and the fix itself inserts the undocumented `conn.private[:plug_router_opts]` (copy_opts_to_assign writes to conn.assigns, not private; plug is not a dep so it can't be verified), which yields nil and turns the compile error into a runtime FunctionClauseError, plus it never checks the module is a Plug.Router so `conn` may be unbound.

## no_underscore_pattern_binding_with_bare_body_use — 2026-07-24
- Files:
  - `lib/semantic/no_underscore_pattern_binding_with_bare_body_use.ex`
  - `test/semantic/no_underscore_pattern_binding_with_bare_body_use_check_test.exs`
  - `test/semantic/no_underscore_pattern_binding_with_bare_body_use_fix_test.exs`
- Reason: dead in production — Elixir never emits `variable "_x" is unused` (verified on the rule's own example and across def-head/assignment/map-pattern/comprehension/fn/case-tuple probes; the real diagnostics there are the `undefined variable "old_name"` error plus `variable "value" is unused`), so match? can never fire; the only real hook is the `undefined variable` family already claimed at priority 500 by FixCaseBranchAssignmentScope (first match wins), so re-aiming needs a lib/semantic.ex fallthrough — out of scope. Separately the fix is unsafe: has_standalone_occurrence? scans the whole source rather than the clause, and replace_in_clause rewrites every `_x` occurrence between the enclosing def and its `end`, including other clauses, string literals and comments; and one fix test's input does not parse (`def handle({:update, _value}), do` -> "unexpected reserved word: do").

## no_unreachable_duplicate_function_clause — 2026-07-24
- Files:
  - `lib/semantic/no_unreachable_duplicate_function_clause.ex`
  - `test/semantic/no_unreachable_duplicate_function_clause_check_test.exs`
  - `test/semantic/no_unreachable_duplicate_function_clause_fix_test.exs`
- Reason: duplicate of the accepted Pattern rule NoDuplicateFunctionClauses, and unsafe — clause_key keys only on {def|defp, name, arity} with no pattern comparison, so fix/2 deletes every later clause of any ordinary multi-clause function (verified: `def fact(0), do: 1` / `def fact(n), do: n * fact(n - 1)` is rewritten to just the base case); the trigger is also wrong (match? fires on the unrelated MatchError family "no match of right hand side value" — nothing to do with unreachable clauses; the real diagnostic is "this clause cannot match because a previous clause…"), the fix ignores the diagnostic entirely and re-renders the whole file via Sourceror.to_string, and even the flagship test's own fix orphans `defp ensure_registry_started/0` into an unused-function warning.

## no_unreachable_function_clause — 2026-07-24
- Files:
  - `lib/semantic/no_unreachable_function_clause.ex`
  - `test/semantic/no_unreachable_function_clause_check_test.exs`
  - `test/semantic/no_unreachable_function_clause_fix_test.exs`
- Reason: dead in production — the "cannot match because a previous clause at line N matches the same pattern" diagnostic family is already claimed at priority 500 by the accepted NoUnreachableCatchAfterRescue (Enum.find first-match-wins, and "Catch" sorts before "Function"), so on the rule's own flagship fixture Semantic.analyze returns [] and Semantic.fix leaves the source unchanged; match? can't be narrowed to win the race (the diagnostic text is identical for both shapes), so re-aiming needs a lib/semantic.ex fallthrough — out of scope. Also overlaps the accepted Pattern rule NoDuplicateFunctionClauses, which deliberately declines the same-head/different-body case this fix deletes, and fix/2 never validates the message (any diagnostic with a {line, col} position deletes whatever def/defp sits on that line) and re-renders the whole file via Sourceror.to_string.

## no_unused_private_function — 2026-07-24
- Files:
  - `lib/semantic/no_unused_private_function.ex`
  - `test/semantic/no_unused_private_function_check_test.exs`
  - `test/semantic/no_unused_private_function_fix_test.exs`
- Reason: breaks 3 accepted end-to-end tests it can't be narrowed away from (test/credence_test.exs:1059 and the two fix_showcase/multi-rule showcase tests deliberately keep unused defps — normalize_words/2 is exactly this rule's flagship shape), and getting the suite green would need edits to those shared test files; the fix also orphans preceding attributes (the credence_test case yields `defmodule Foo do @doc false end`), and check/fix disagree whenever a @spec is present or the module body isn't a __block__ — call_exists? counts the defp head and the `@spec helper(integer())` node as calls, so the rule reports the issue and then silently no-ops.

## no_validation_rejects_infinity_for_timeout — 2026-07-24
- Files:
  - `lib/semantic/no_validation_rejects_infinity_for_timeout.ex`
  - `test/semantic/no_validation_rejects_infinity_for_timeout_check_test.exs`
  - `test/semantic/no_validation_rejects_infinity_for_timeout_fix_test.exs`
- Reason: dead in production and behaviour-changing — "must be a positive integer" is a user raise-message string, never an Elixir compiler diagnostic, so on the rule's own flagship fixture compile_and_capture returns {:ok, []}, Semantic.analyze returns [] and Semantic.fix leaves the source unchanged (verified); the tests only pass because they hand-fabricate a diagnostic map and call match?/fix directly, bypassing the phase. Even if it fired, the fix rewrites the user's validation policy rather than resolving a diagnostic: for timeout == :infinity before raises ArgumentError and after returns :ok, and for 0/-1/nil/"5000" the raised message changes (verified before/after in elixir) — a different answer on admitted inputs. fix/2 also ignores the diagnostic entirely (_diagnostic), postwalking the whole file so any `unless is_integer(x) and x > 0` block anywhere is rewritten regardless of the reported line, and mutates every string literal containing the phrase inside that block's do-body.

## prefer_double_quoted_atom — 2026-07-24
- Files:
  - `lib/semantic/prefer_double_quoted_atom.ex`
  - `test/semantic/prefer_double_quoted_atom_check_test.exs`
  - `test/semantic/prefer_double_quoted_atom_fix_test.exs`
- Reason: check and fix target disjoint diagnostics — Elixir 1.20 emits "single quotes around atoms are deprecated. Use double quotes instead" for `:'atom'` (verified), not the charlist message the rule matches, so on its own flagship `:'$end_of_table'` fixture Semantic.analyze returns [] and Semantic.fix leaves the source unchanged; conversely it claims the bare-charlist `'hello'` diagnostic (already the accepted Pattern rule PreferSigilCharlist's shape), misattributes it to :prefer_double_quoted_atom, and then its fix is a no-op on it — flagging what it won't fix. Worse, the fix ignores the diagnostic position and regex-replaces `:'([^\'\']*)'` across the whole file, so once it matches the charlist warning it silently corrupts unrelated code: verified end-to-end that Semantic.fix rewrites `def b, do: 'a:' ++ 'b'` into `def b, do: 'a:" ++ "b'` — a different value that still compiles. Repairing it means re-aiming the message AND replacing the entire fix with a position-anchored, escape/interpolation-aware rewrite, and match?/1 has no source access to keep check/fix agreed on unsafe atom bodies without a shared-file change.

## prefer_explicit_range_step — 2026-07-24
- Files:
  - `lib/semantic/prefer_explicit_range_step.ex`
  - `test/semantic/prefer_explicit_range_step_fix_test.exs`
- Reason: the //1 special case inverts the fix's safety — `3..-1` already IS `3..-1//-1` (verified `3..-1 === 3..-1//-1` is true, struct step: -1, and the compiler itself says "please write 3..-1//-1"), so `//-1` was the byte-identical no-op and `//1` is the value change; the rule patches every descending literal range in the file with no notion of context, so verified through the real Credence.Semantic.fix `def f, do: Enum.sum(3..-1)` becomes `Enum.sum(3..-1//1)`, changing the answer from 5 to 0 (`Enum.to_list`: `[3,2,1,0,-1]` → `[]`) — the delta's own tests miss this because String.slice/Enum.slice back-compat makes all three step forms coincide there, the only context where its premise holds.

## prefer_pattern_match_for_non_empty_list — 2026-07-24
- Files:
  - `lib/semantic/prefer_pattern_match_for_non_empty_list.ex`
  - `test/semantic/prefer_pattern_match_for_non_empty_list_check_test.exs`
  - `test/semantic/prefer_pattern_match_for_non_empty_list_fix_test.exs`
- Reason: no same-answer fix exists (`[_ | _] = items` matches improper lists that `length(items) > 0` rejects — verified `case [1 | 2]` flips :other -> {:nonempty, [1|2]}), and the fix discards the clause pattern entirely, so `{a, items} when length(items) > 0 -> {a, items}` is rewritten to `[_ | _] = items -> {a, items}` (verified via the rule's own fix/2), which no longer matches a tuple and leaves `a` undefined; check/fix also disagree by construction since match?/1 sees only the message and flags `def f(x) when length(x) > 0` and `is_list(x) and length(x) > 0`, both of which fix/2 leaves untouched (verified).

## undefined_function — 2026-07-24
- Files:
  - `lib/semantic/undefined_function.ex`
  - `test/semantic/undefined_function_check_test.exs`
  - `test/semantic/undefined_function_qualified_fix_test.exs`
- Reason: the delta hijacks the unrelated "single quotes around atoms are deprecated" warning (Elixir 1.20 emits it for `:'hello'`, verified) to drive an :ets.insert/3 rewrite, so match?/1 now returns true on that deprecation while fix/2 is a verified no-op on it (check/fix disagree on a real diagnostic), and on a line carrying both the deprecated atom and a 3-arg call it silently rewrites `:ets.insert(t, :'k', 1)` → `:ets.insert(t, {:'k', 1})` (verified through the rule's own fix/2) — a different call — while leaving the reported deprecation unfixed; meanwhile the genuine `:ets.insert/3` diagnostic is ":ets.insert/3 is undefined or private" (verified), which never reaches that code path. The Integer.is_even/1 addition is likewise mis-aimed: the compiler always appends "Be sure to require Integer" (verified for both `&Integer.is_even/1` and `Integer.is_even(n)`), so parse_require_hint always wins and the :capture_to_lambda branch is dead code — its three flagship tests pin a message the compiler never emits — while the live insert_require path no-ops whenever any other module in the file already contains `require Integer` (verified), disagreeing with check again.

## fix_after_clause_pattern_arrow — 2026-07-24
- Files:
  - `lib/syntax/fix_after_clause_pattern_arrow.ex`
  - `test/syntax/fix_after_clause_pattern_arrow_analyze_test.exs`
  - `test/syntax/fix_after_clause_pattern_arrow_fix_test.exs`
- Reason: wrong phase (target parses, so Syntax never runs it — Credence.analyze returns no issues on its own flagship input); fix output still fails to compile (undefined pattern vars), check/fix disagree on single-line `pat -> body`, and the blind first-`after`-line scan strips the timeout clause from a valid multiline `receive ... after 1000 ->` in the same file.

## fix_block_expression_as_pipe_left — 2026-07-24
- Files:
  - `lib/syntax/fix_block_expression_as_pipe_left.ex`
  - `test/syntax/fix_block_expression_as_pipe_left_analyze_test.exs`
  - `test/syntax/fix_block_expression_as_pipe_left_fix_test.exs`
- Reason: wrong phase — the flagship input parses, so Syntax never runs it (Credence.analyze returns valid: true, no issues) and Syntax.fix skips the pipeline; also check/fix disagree, as the `~r/\|>.*&\d/` line scan flags valid `xs |> Enum.map(&(&1 * 2))` that fix correctly refuses to touch.

## fix_div_rem — 2026-07-24
- Files:
  - `lib/syntax/fix_div_rem.ex`
  - `test/syntax/fix_div_rem_test.exs`
- Reason: right-operand regex `(\w+|\([^)]*\))` regresses call/dotted right operands — `x = total div length(list)` now yields `div(total, length)(list)` (and `a div b.c` → `div(a, b).c`), which the accepted rest-of-line version got right; nested calls like `div a, f(g(b))` can't be covered by that alternation either.

## fix_do_equals_keyword_syntax — 2026-07-24
- Files:
  - `lib/syntax/fix_do_equals_keyword_syntax.ex`
  - `test/syntax/fix_do_equals_keyword_syntax_analyze_test.exs`
  - `test/syntax/fix_do_equals_keyword_syntax_fix_test.exs`
- Reason: duplicate/dead — accepted FixDoBlockFusion's `@comma_do_midline` already claims `, do <expr>` and runs first (same priority 500, "FixDoB" < "FixDoE"), rewriting `def f(x), do = x + 1` to `, do: = x + 1` so this rule's regex never matches in the pipeline; the correct fold is into FixDoBlockFusion (out of set). Its own compound branch is also unsafe: `for x <- l, do = x + 1 do\n  result\nend` silently DELETES the block body `result`, and the branch is exclusive — a file with both forms leaves the plain `, do = x - 1` unfixed yet still flagged (check/fix disagree, output still doesn't parse).

## fix_ets_options_bare_keypos — 2026-07-24
- Files:
  - `lib/syntax/fix_ets_options_bare_keypos.ex`
  - `test/syntax/fix_ets_options_bare_keypos_analyze_test.exs`
  - `test/syntax/fix_ets_options_bare_keypos_fix_test.exs`
- Reason: wrong phase + silently corrupts valid code — `:ets.new(t, [:set, :keypos, 1])` parses fine so the Syntax round (only runs when Sourceror fails) never reaches it; on a file broken elsewhere the line regex rewrites valid `Keyword.get(opts, :keypos, 1)`/`Map.get(m, :keypos, 0)` into 2-arg tuple calls, `def handle(:keypos, 1)` into arity-1, and `{ :keypos, 1}` (space) into `{ {:keypos, 1}}` — all still parse, so the damage is silent; belongs in the Pattern round as an AST rule on `:ets.new/2` args (new file, outside this set).

## fix_if_inline_else_case_block — 2026-07-24
- Files:
  - `lib/syntax/fix_if_inline_else_case_block.ex`
  - `test/syntax/fix_if_inline_else_case_block_analyze_test.exs`
  - `test/syntax/fix_if_inline_else_case_block_fix_test.exs`
- Reason: wrong phase — `if c, do: v, else:` + multi-line `case` parses fine (Sourceror :ok), so the Syntax round (only runs when parsing fails) never reaches it; verified `Credence.Syntax.analyze/fix` are no-ops on the rule's own test input. On a file broken elsewhere the line regexes rewrite non-code text (confirmed: it rewrote the bad-shape example inside a `@moduledoc` heredoc). Belongs in the Pattern round as an AST rule on the broken `if/3` node (new file, outside this set).

## fix_map_arrow_in_list_bracket — 2026-07-24
- Files:
  - `lib/syntax/fix_map_arrow_in_list_bracket.ex`
  - `test/syntax/fix_map_arrow_in_list_bracket_analyze_test.exs`
  - `test/syntax/fix_map_arrow_in_list_bracket_fix_test.exs`
- Reason: unguarded global regex fix/1 runs on every unparseable file (syntax.ex has no analyze gate) and corrupts valid code — e.g. `[%{atom() => any()}]` (list-of-maps spec) -> `[{%{atom(), any()}}]`, `[x, %{a => b}]` -> `[{x, %{a, b}}]`, rewrites comments/strings/heredocs, and the multi-pair `[a => b, c => d]` -> invalid `[{a, b, c => d}]`; needs the sibling's heredoc/comment/string discipline plus map-brace disambiguation (re-author, not a narrow).

## fix_mixed_required_optional_map_keys — 2026-07-24
- Files:
  - `lib/syntax/fix_mixed_required_optional_map_keys.ex`
  - `test/syntax/fix_mixed_required_optional_map_keys_analyze_test.exs`
  - `test/syntax/fix_mixed_required_optional_map_keys_fix_test.exs`
- Reason: fix/1 regex `%\{.*?optional\(/s` runs on every unparseable file (no analyze gate) and spans from the first `%{` to the first `optional(` across the whole file — corrupts earlier valid maps, `optional()` function calls, and string/comment/heredoc contents (all confirmed). Same class as sibling fix_map_arrow_in_list_bracket; needs a re-author with string/comment/heredoc discipline and single-map boundary detection, not a narrow.

## fix_oop_style_method_call_syntax — 2026-07-24
- Files:
  - `lib/syntax/fix_oop_style_method_call_syntax.ex`
  - `test/syntax/fix_oop_style_method_call_syntax_analyze_test.exs`
  - `test/syntax/fix_oop_style_method_call_syntax_fix_test.exs`
- Reason: false premise — `foo.bar?(foo)` is valid parseable Elixir (1-arg call `foo.bar?/1`), not a syntax error; the "fix" to `foo.bar?` drops the arg → 0-arg access, never the same answer, so no safe narrow core; also same unguarded global-regex class as sibling syntax rules — fix/1 corrupts valid `foo.bar?(foo)` occurrences in any file that fails to parse for an unrelated reason (demonstrated).

## fix_pin_on_non_variable — 2026-07-24
- Files:
  - `lib/syntax/fix_pin_on_non_variable.ex`
  - `test/syntax/fix_pin_on_non_variable_analyze_test.exs`
  - `test/syntax/fix_pin_on_non_variable_fix_test.exs`
- Reason: False premise / wrong phase — `^{key}` parses fine (compile-time semantic error, not a parse error). The syntax phase (lib/syntax.ex) only runs rule analyze/fix when Sourceror.parse_string FAILS, but this rule's analyze/fix only produce output when it SUCCEEDS — mutually exclusive, so the rule is inert in the pipeline. Belongs in the semantic phase (out-of-scope shared change); green tests only pass by calling analyze/fix directly, bypassing the phase gate.

## fix_python_format_in_string_interpolation — 2026-07-24
- Files:
  - `lib/syntax/fix_python_format_in_string_interpolation.ex`
  - `test/syntax/fix_python_format_in_string_interpolation_analyze_test.exs`
  - `test/syntax/fix_python_format_in_string_interpolation_fix_test.exs`
- Reason: unguarded global-regex fix/1 runs on every unparseable file (syntax.ex has no analyze gate) and corrupts valid code — the literal `#{name:02}` inside a non-interpolating `~S` sigil (and inside `#` comments) is rewritten, changing the string's runtime value (confirmed). Same class as sibling syntax rules; distinguishing real `"..."` interpolation from literal sigil/comment text needs string/heredoc/sigil lexing on unparseable input (no AST) — a re-author, not a narrow.

## fix_python_spread_in_map — 2026-07-24
- Files:
  - `lib/syntax/fix_python_spread_in_map.ex`
  - `test/syntax/fix_python_spread_in_map_analyze_test.exs`
  - `test/syntax/fix_python_spread_in_map_fix_test.exs`
- Reason: unguarded global-regex fix/1 runs on the whole source of every unparseable file (syntax.ex has no analyze gate) and rewrites the `%{..**var..}` pattern inside valid string literals and inline comments — e.g. `"Python uses %{a: 1, **rest}"` becomes `"Python uses Map.merge(%{a: 1}, rest)"`, changing the string's runtime value (confirmed). Same class as sibling syntax rules; safely distinguishing a real `**` spread from one inside a string/sigil/heredoc/inline-comment needs full lexing of unparseable input (no AST), a re-author not a narrow.

## fix_rescue_struct_pattern — 2026-07-24
- Files:
  - `lib/syntax/fix_rescue_struct_pattern.ex`
  - `test/syntax/fix_rescue_struct_pattern_analyze_test.exs`
  - `test/syntax/fix_rescue_struct_pattern_fix_test.exs`
- Reason: unguarded global-regex fix/1 runs on the whole source of every unparseable file (syntax.ex has no analyze gate) — the regex %([A-Za-z_]\w*)\s*-> rewrites `%Foo ->` text inside valid string literals/comments/sigils (e.g. "in Python you write %ValueError -> handler" → "...e in ValueError -> handler"), changing runtime value (confirmed). Same class as sibling syntax rules; distinguishing a real rescue-clause pattern from string/comment/sigil text on unparseable input (no AST) needs full lexing — a re-author, not a narrow.

## fix_stray_comma_before_when_guard — 2026-07-24
- Files:
  - `lib/syntax/fix_stray_comma_before_when_guard.ex`
  - `test/syntax/fix_stray_comma_before_when_guard_analyze_test.exs`
  - `test/syntax/fix_stray_comma_before_when_guard_fix_test.exs`
- Reason: unguarded global-regex fix/1 runs on the whole source of every unparseable file (syntax.ex has no analyze gate) and rewrites `),\s*when` inside valid string literals and comments — e.g. `@msg "call foo(x), when ready"` becomes `"call foo(x) when ready"`, changing the string's runtime value (confirmed). Same class as sibling syntax rules; safely distinguishing a real function-clause when-guard from `), when` inside a string/sigil/heredoc/comment on unparseable input (no AST) needs full lexing — a re-author, not a narrow.

## fix_struct_field_assignment_syntax — 2026-07-24
- Files:
  - `lib/syntax/fix_struct_field_assignment_syntax.ex`
  - `test/syntax/fix_struct_field_assignment_syntax_analyze_test.exs`
  - `test/syntax/fix_struct_field_assignment_syntax_fix_test.exs`
- Reason: Wrong phase + inert — target `left.right = node` PARSES fine (compile-time semantic error, not a parse error), so the syntax phase (which only runs on parse failure) never invokes it; green tests only pass by calling analyze/fix directly. When it does run on files unparseable for other reasons, the unguarded global regex rewrites `var.field = expr` inside string literals/heredocs (`server.host = localhost` → `server = %{server | host: localhost}`), changing runtime values. Moving to the semantic phase is a shared/out-of-scope change; safe text/code separation needs full lexing (re-author).

## fix_truncated_module_reference — 2026-07-24
- Files:
  - `lib/syntax/fix_truncated_module_reference.ex`
  - `test/syntax/fix_truncated_module_reference_analyze_test.exs`
  - `test/syntax/fix_truncated_module_reference_fix_test.exs`
- Reason: unguarded global-regex fix/1 runs on the whole source of every unparseable file (syntax.ex has no analyze gate) and rewrites the literal `__MODULE%` inside valid string literals/comments — e.g. `@template "render __MODULE% placeholder"` becomes `"render __MODULE__ placeholder"`, changing the string's runtime value (confirmed) without repairing the real parse error. Same class as sibling syntax rules; distinguishing a real code `__MODULE%` from string/comment/sigil text on unparseable input (no AST) needs full lexing — a re-author, not a narrow.

## fix_when_guard_in_for_comprehension — 2026-07-24
- Files:
  - `lib/syntax/fix_when_guard_in_for_comprehension.ex`
  - `test/syntax/fix_when_guard_in_for_comprehension_analyze_test.exs`
  - `test/syntax/fix_when_guard_in_for_comprehension_fix_test.exs`
- Reason: unguarded fix/1 runs on whole source of every unparseable file — new-line regex ^(\s+)when\s+ strips `when` from VALID multi-line function guards whenever any preceding line has a `for ... <-` (confirmed: `def b(x)\n  when x>0` -> `x>0`, guard broken), and same-line `, when` rewrites string-literal/moduledoc content containing a for-comprehension example; same class as accepted siblings, needs full lexing (re-author).

## no_after_or_rescue_in_case — 2026-07-24
- Files:
  - `lib/syntax/no_after_or_rescue_in_case.ex`
  - `test/syntax/no_after_or_rescue_in_case_analyze_test.exs`
  - `test/syntax/no_after_or_rescue_in_case_fix_test.exs`
- Reason: Wrong phase + inert — target `case … after … rescue … end` PARSES fine (compile-time "unexpected option :after in case" semantic error, not a parse error), so the syntax phase (which only runs rules on parse failure) never invokes it; probe confirmed Syntax.analyze=[] and Syntax.fix is a no-op. Green tests pass only by calling analyze/fix directly. Belongs in the semantic phase (shared/out-of-scope change); same class as fix_struct_field_assignment_syntax.

## no_arrow_operator_outside_comprehension — 2026-07-24
- Files:
  - `lib/syntax/no_arrow_operator_outside_comprehension.ex`
  - `test/syntax/no_arrow_operator_outside_comprehension_analyze_test.exs`
  - `test/syntax/no_arrow_operator_outside_comprehension_fix_test.exs`
- Reason: Wrong phase + inert — `<-` outside for/with PARSES fine (compile-time "undefined function <-/2" semantic error, not a parse error), so the syntax phase (runs rules only on parse failure) never invokes it; confirmed test input parses_ok=true so Syntax.analyze=[]/Syntax.fix is a no-op. Compounding: the rule's own find_standalone_arrows needs Sourceror.parse_string to SUCCEED, so on the unparseable inputs the phase does run it on, it's a no-op. Green tests pass only by calling analyze/fix directly. Belongs in the semantic phase (shared/out-of-scope change); same class as no_after_or_rescue_in_case and fix_struct_field_assignment_syntax.

## no_atom_as_function_name — 2026-07-24
- Files:
  - `lib/syntax/no_atom_as_function_name.ex`
  - `test/syntax/no_atom_as_function_name_analyze_test.exs`
  - `test/syntax/no_atom_as_function_name_fix_test.exs`
- Reason: unguarded global-regex fix/1 (no parse gate, no error-location targeting) runs on the whole source of every unparseable file and rewrites `:word(` inside valid string literals/comments — confirmed `"see :setup(opts)"` -> `"see setup(opts)"`, changing the string's runtime value; target is a real parse error (correct phase, unlike recent siblings) but a safe version needs parser-error-location targeting/lexing to tell code from string/comment on unparseable input — a re-author, not a narrow.

## no_bare_atom_in_genserver_start_link — 2026-07-24
- Files:
  - `lib/syntax/no_bare_atom_in_genserver_start_link.ex`
  - `test/syntax/no_bare_atom_in_genserver_start_link_analyze_test.exs`
  - `test/syntax/no_bare_atom_in_genserver_start_link_fix_test.exs`
- Reason: Wrong phase + inert — target GenServer.start_link with bare-atom/`||` third arg PARSES fine (runtime FunctionClauseError, not a parse error), so the syntax phase (runs rules only on parse failure) never invokes it; Credence.Syntax.analyze=[]/fix is a no-op on the target. Rule's own analyze/fix also require parse success, so it's doubly inert. Green tests pass only by calling the module directly. Belongs in the semantic phase (shared/out-of-scope re-author); same class as no_arrow_operator_outside_comprehension / no_after_or_rescue_in_case.

## no_bare_case_in_map — 2026-07-24
- Files:
  - `lib/syntax/no_bare_case_in_map.ex`
  - `test/syntax/no_bare_case_in_map_analyze_test.exs`
  - `test/syntax/no_bare_case_in_map_fix_test.exs`
- Reason: Wrong phase + inert — bare `case` in a map literal PARSES fine (syntactically valid, non-idiomatic only), so the syntax phase (runs rules only on parse failure) never invokes it; probe confirms Credence.Syntax.analyze=[]/fix is a no-op on the target. Rule's own analyze/fix also require parse success, so it's doubly inert. Green tests pass only by calling the module directly. Belongs in the semantic/pattern phase (shared/out-of-scope re-author); same class as no_arrow_operator_outside_comprehension / no_after_or_rescue_in_case.

## no_capture_as_identity_function — 2026-07-24
- Files:
  - `lib/syntax/no_capture_as_identity_function.ex`
  - `test/syntax/no_capture_as_identity_function_analyze_test.exs`
  - `test/syntax/no_capture_as_identity_function_fix_test.exs`
- Reason: Wrong phase + inert — bare `&identifier` PARSES fine (compile-time "invalid args for &", not a parse error), so the syntax phase (runs rules only on parse failure) never invokes it; probe confirms Sourceror.parse_string={:ok,_}, Credence.Syntax.analyze=[] and Syntax.fix is a no-op on the target. Docstring's "always fails to parse" claim is false. Green tests pass only by calling analyze/fix directly. Belongs in the semantic phase; same class as no_arrow_operator_outside_comprehension / no_after_or_rescue_in_case.

## no_catch_in_receive — 2026-07-27
- Files:
  - `lib/syntax/no_catch_in_receive.ex`
  - `test/syntax/no_catch_in_receive_analyze_test.exs`
  - `test/syntax/no_catch_in_receive_fix_test.exs`
- Reason: Wrong phase + inert — `receive do … catch … end` PARSES fine (compile-time "unexpected option :catch in receive", not a parse error), so the syntax phase (runs rules only on parse failure) never invokes it; probe confirms Sourceror.parse_string={:ok,_}, Credence.Syntax.analyze=[] and Syntax.fix logs "source already parses, skipping" (no-op). Rule's own analyze/fix also require parse success, so it's doubly inert. Green tests pass only by calling the module directly. Belongs in the semantic phase; same class as no_bare_case_in_map / no_capture_as_identity_function.

## no_defp_qualified_name — 2026-07-27
- Files:
  - `lib/syntax/no_defp_qualified_name.ex`
  - `test/syntax/no_defp_qualified_name_analyze_test.exs`
  - `test/syntax/no_defp_qualified_name_fix_test.exs`
- Reason: Wrong phase + inert — `defp Macro.expand(...)` PARSES fine (probe: Sourceror.parse_string=:ok, Credence.Syntax.analyze=[], Syntax.fix no-op), so the syntax phase never invokes it; docstring's "invalid Elixir syntax" claim is false (it's a compile error). Fix is also unsafe even if re-phased: the call-site regex is unanchored, so it rewrites EVERY `Mod.fun(` in the file including genuine calls to the real module (used-elsewhere trap), and `Macro.underscore("Foo.Bar") = "foo/bar"` yields `foo/bar_baz(` — unparseable output for the dotted modules its own regex admits. Same class as no_catch_in_receive / no_capture_as_identity_function.

## no_elif_keyword — 2026-07-27
- Files:
  - `lib/syntax/no_elif_keyword.ex`
  - `test/syntax/no_elif_keyword_analyze_test.exs`
  - `test/syntax/no_elif_keyword_fix_test.exs`
- Reason: Duplicate of accepted fix_elsif_in_if_chain (same bad habit, its moduledoc already names Python `elif`) but is the pre-hardening copy — corrupts heredoc doc text, mangles chains with no `end` at header indent, re-indents multi-line strings, and analyze flags every `elif` while fix bails; fold `elif` into fix_elsif_in_if_chain's regexes (shared-file change, out of scope).

## no_else_in_for_comprehension — 2026-07-27
- Files:
  - `lib/syntax/no_else_in_for_comprehension.ex`
  - `test/syntax/no_else_in_for_comprehension_analyze_test.exs`
  - `test/syntax/no_else_in_for_comprehension_fix_test.exs`
- Reason: Wrong phase + inert, and fix crashes — `for ... do ... else ... end` PARSES fine (compile-time "unsupported option :else given to for", not a parse error), so the syntax phase (runs rules only on parse failure) never invokes it; probe: Sourceror.parse_string=:ok, Credence.Syntax.analyze=[], Syntax.fix logs "source already parses, skipping" (no-op) even though the rule IS discovered. Its own analyze/fix also require parse success, so it's doubly inert; green tests pass only by calling the module directly. Separately, the line-range fix is broken on the keyword form `for x <- l, do: x, else: (_ -> [])`: analyze flags it but for_meta[:end] is nil → fix raises ArithmeticError (nil - 2). Belongs in the semantic phase (out-of-scope shared/new-file change); same class as no_catch_in_receive / no_defp_qualified_name.

## no_elsif_keyword — 2026-07-27
- Files:
  - `lib/syntax/no_elsif_keyword.ex`
  - `test/syntax/no_elsif_keyword_analyze_test.exs`
  - `test/syntax/no_elsif_keyword_fix_test.exs`
- Reason: Duplicate of accepted fix_elsif_in_if_chain (same `elsif`-in-`if` habit, byte-identical `cond` output) and is the pre-hardening copy — corrupts heredoc doc text and emits garbage when the chain has no terminator at header indent; analyze flags every `elsif` while fix bails. Folding it in would mean editing the accepted rule (shared/other-set file, out of scope).

## no_if_else_in_receive_after — 2026-07-27
- Files:
  - `lib/syntax/no_if_else_in_receive_after.ex`
  - `test/syntax/no_if_else_in_receive_after_analyze_test.exs`
  - `test/syntax/no_if_else_in_receive_after_fix_test.exs`
- Reason: Wrong phase + inert, and check/fix disagree — `receive do ... after if true do ... end end` PARSES fine (`Code.string_to_quoted` = :ok; failure is the compile-time "expected a single -> clause for :after in \"receive\""), so the syntax phase (lib/syntax.ex runs rules only on `Sourceror.parse_string` = {:error,_}) never invokes it; the rule's own analyze/fix also require parse success, so it is doubly inert and its green tests pass only by calling the module directly. Separately, `render_receive_fix`/`find_receive` always patch the FIRST `receive` node in the file while the prewalk fixes the first receive with a bare `after`: with a valid `receive` ahead of the offending one, analyze flags the issue but fix returns the source byte-identical (verified via the real test file). Belongs in the semantic phase (new shared/out-of-scope file); same class as the accepted-followup no_else_in_for_comprehension.

## no_keyword_if_in_tuple — 2026-07-27
- Files:
  - `lib/syntax/no_keyword_if_in_tuple.ex`
  - `test/syntax/no_keyword_if_in_tuple_analyze_test.exs`
  - `test/syntax/no_keyword_if_in_tuple_fix_test.exs`
- Reason: Unsafe and crashes — `Credence.Syntax.fix("x = foo(1, a: 2, 3)\n")` RAISES (find_last_kw returns its nil accumulator; the `:not_found` case clause is dead), and that input is the domain of the already-accepted fix_keyword_before_positional_argument, whose exact error fragment this rule also claims; the closing paren is placed by a quote-blind character walk so `{if a, do: 1, else: "p, q", b}` becomes `{(if a, do: 1, else: "p), q", b}` (paren inside the string, output does not parse) and the opening paren comes from a backward `\b(if|case|cond|unless)\b` regex that hits unrelated words, incl. inside strings and on earlier lines (`x = {if a > 0,\n do: label(a, "upper case"),\n else: 0, a}` -> paren inside "upper (case"; `if a, do: 1\nx = [key: 1, do: 2, 3]` -> `(if a, do: 1\n... do: 2), 3]`), both still unparseable; analyze flags every "unexpected expression after keyword list" error regardless of whether fix can repair it, so check/fix disagree. Same bad habit and identical repair as the accepted no_keyword_if_bare_in_tuple (bare keyword `if`/`unless` in a container, wrapped in parens; only the parser error differs by whether the `if` is the first element), whose parser-validated span search is the safe mechanism — fold this error fragment into that rule (out-of-scope file).

## no_mixed_script_identifier — 2026-07-27
- Files:
  - `lib/syntax/no_mixed_script_identifier.ex`
  - `test/syntax/no_mixed_script_identifier_analyze_test.exs`
  - `test/syntax/no_mixed_script_identifier_fix_test.exs`
- Reason: Its only fix is to DELETE user code, and it deletes far more than the defmodule it claims to target — analyze fires on every "invalid mixed-script identifier found" error, which the tokenizer raises for ANY identifier anywhere (variable, function name), not just a glued `defmodule补偿State`; `remove_block_at` then blindly deletes from the error line to whatever the regex `do`/`end` walk calls the closing `end`. Verified: `defmodule A do\n def run do\n  xИ = 1\n  xИ\n end\nend` -> the walk never rebalances so it drops lines 3..EOF, yielding `defmodule A do\n  def run do` (does NOT parse — the fix removes the module's own `end`s); `xИ = 1\nIO.puts(:ok)` -> empty file (unrelated code deleted); `defmodule A do\n def 补偿State do ... end\nend` -> silently deletes a whole function; `defmodule补偿State do\n def hello, do: "the end"\nend\n\ndefmodule Saga do ...` -> the quote-blind `\bend\b` counts "end" inside the string literal, mis-locating the boundary and leaving a stray `end` (does NOT parse). The moduledoc's whole premise ("the hallucinated block is always a duplicate of a valid defmodule already present in the same file") is asserted but never checked by the code, so a non-duplicate `defmodule补偿State do def unique_logic, do: 42 end` is erased to an empty file. There is no safe core to narrow to: a mixed-script identifier is unrepresentable in Elixir, so no rewrite can preserve meaning, and deletion is a guess that a maintainer — not the rule — should make; salvaging it would need parser-validated span search plus real duplicate detection, i.e. a rewrite rather than a narrowing.

## no_nested_capture — 2026-07-27
- Files:
  - `lib/syntax/no_nested_capture.ex`
  - `test/syntax/no_nested_capture_analyze_test.exs`
  - `test/syntax/no_nested_capture_fix_test.exs`
- Reason: Wrong phase and mangles code — nested captures PARSE fine (`Code.string_to_quoted("&Map.update(&1, 0, &(&1 + 1))")` -> `{:ok, ...}`; the failure is the compile-time diagnostic "nested captures are not allowed"), but `Credence.Syntax.analyze/2` returns `[]` and `fix_with_trace/2` skips the whole pipeline whenever the source parses, so this rule is dead in production except by accident (a file with some *unrelated* parse error that an earlier-priority rule repairs mid-reduce); its home is the Semantic phase, which matches error-severity diagnostics — that's a new `lib/semantic/no_nested_capture.ex` with `match?/1`+`to_issue/1`+`fix/2`, i.e. a different set, out of scope here. Even ignoring the phase, the fix corrupts real inputs: doubly-nested captures emit overlapping Sourceror patches (`&f(&1, &(&2 + &(&3)))` -> `&f(&1, fn x, y, z -> y + (&z) endy, z -> z end)))`, verified does NOT parse); a `fn` inside the outer capture isn't a depth reset and the range misses the closing paren (`&Task.async(fn -> &(&1) end)` -> `&Task.async(fn -> fn x -> x end) end)`, verified does NOT parse); and the `not is_integer(arg)` guard swallows named captures, so the extremely common `&Enum.map(&1, &String.upcase/1)` (a genuine nested-capture error) becomes `&Enum.map(&1, fn -> String.upcase() / 1 end)` — it compiles, then calls 0-arity `String.upcase()` and divides, silently broken. The safe core (a single, non-doubly-nested, paren-form `&(...)` whose body holds only `&N`) is exactly what the shipped tests cover, but narrowing to it still leaves a rule its own phase can never invoke.

