defmodule Credence.BehaviourEquivalence do
  @moduledoc """
  Behaviour-equivalence assertions for Pattern rule fixes.

  A rule's fix is only correct if `eval(original)` and `eval(fixed)` produce
  the *same outcome* on every input — not just the inputs the author imagined.
  These assertions run the before- and after-code over a curated adversarial
  input set and assert identical outcomes, **including exception parity**
  (an `ArithmeticError`-vs-`ArgumentError` swap is a divergence, not a pass).

  This is plain `mix test` machinery — a third kind of per-rule test alongside
  `_check_test.exs` / `_fix_test.exs`. There is no separate runner.

  ## Three tiers (pick the one that fits the rule's fix)

    * `assert_equivalent/2` — **T1 expression**. The fix rewrites a
      self-contained expression; we wrap before/after in `fn <vars> -> expr end`
      and apply per input.
    * `assert_equivalent_module/2` — **T2 module-call**. The fix is
      def/module-structural; we compile the whole before- and after-module
      under unique names and invoke a function over inputs.
    * `assert_effect_trace_equivalent/2` — **PROBE**. For fixes that reorder or
      re-evaluate a user transform/predicate, where values can match while the
      call order/count diverges. The transform hole is a free var `effect`;
      we supply a recording fn and assert the call-trace is identical.

  Rules with no runtime behaviour to compare use `mark_equivalence_cosmetic/1`
  (provably inert) or `mark_equivalence_unconstructible/1` (behavioural but no
  self-contained callable example) — both demand a reason.

  ## Anti-stub checks (no external gate needed)

  Every assertion first proves the rule *fires* on the snippet and that a
  *rewrite actually happened*, and enforces a minimum of 3 inputs
  (override with `allow_few_inputs: true`). A stub test therefore fails here,
  not in some meta-test.

  Generalized from `no_manual_frequencies_fix_test.exs` (the `eval1` /
  `assert_preserves` exemplar).
  """

  import ExUnit.Assertions

  alias Credence.RuleHelpers

  @min_inputs 3

  # ── T1: expression-level ──────────────────────────────────────────────

  @doc """
  Assert the rule's fix preserves behaviour over `inputs`, evaluating the
  before/after expression as `fn <vars> -> expr end`.

  Opts:
    * `:rule` (req) — the rule module.
    * `:vars` (req) — ordered free-var names, e.g. `[:list]` or `[:list, :idx]`.
    * `:inputs` (req) — input set. For a single var, each element is the arg.
      For multiple vars, each element is a tuple/list of args.
    * `:compare_messages` — also compare exception messages (default false:
      module-only).
    * `:allow_few_inputs` — allow < #{@min_inputs} inputs (visible in review).
  """
  def assert_equivalent(before_expr, opts) do
    rule = Keyword.fetch!(opts, :rule)
    vars = opts |> Keyword.fetch!(:vars) |> List.wrap()
    inputs = Keyword.fetch!(opts, :inputs)
    compare_messages? = Keyword.get(opts, :compare_messages, false)

    fixed = precheck!(rule, before_expr, inputs, opts)

    orig = compile_fn!(vars, before_expr)
    new = compile_fn!(vars, fixed)

    for input <- inputs do
      args = to_args(input, vars)
      o = eval_outcome(fn -> apply(orig, args) end, compare_messages?)
      n = eval_outcome(fn -> apply(new, args) end, compare_messages?)

      # Strict `===`: `6 == 6.0` is true but they are different values — value-kind
      # (int↔float) changes are exactly what this suite must catch.
      assert o === n, divergence_msg(rule, input, o, n, before_expr, fixed)
    end

    :ok
  end

  # ── T2: module-level ──────────────────────────────────────────────────

  @doc """
  Assert the rule's fix preserves behaviour by compiling the whole before- and
  after-**module** (under unique names) and invoking a function over `inputs`.

  Opts:
    * `:rule` (req) — the rule module.
    * `:call` (req) — `{fun_atom, arity}`; the function to invoke.
    * `:inputs` (req) — input set. Each element is the args (a tuple/list for
      arity > 1, or a bare value for arity 1).
    * `:compare_messages`, `:allow_few_inputs` — as `assert_equivalent/2`.
  """
  def assert_equivalent_module(before_module, opts) do
    rule = Keyword.fetch!(opts, :rule)
    {fun, arity} = Keyword.fetch!(opts, :call)
    inputs = Keyword.fetch!(opts, :inputs)
    compare_messages? = Keyword.get(opts, :compare_messages, false)

    fixed = precheck!(rule, before_module, inputs, opts)

    orig_mod = compile_module!(before_module, "Before")
    new_mod = compile_module!(fixed, "After")

    for input <- inputs do
      args = args_by_arity(input, arity)
      o = eval_outcome(fn -> apply(orig_mod, fun, args) end, compare_messages?)
      n = eval_outcome(fn -> apply(new_mod, fun, args) end, compare_messages?)

      assert o === n, divergence_msg(rule, input, o, n, before_module, fixed)
    end

    :ok
  end

  # ── PROBE: eval-order / double-eval ───────────────────────────────────

  @doc """
  Assert that the rule's fix preserves not just values but the **order and
  count** of calls to a user-supplied transform/predicate.

  The before/after expression must reference a free var `effect` (a 1-arg fn)
  in the transform/predicate position. We supply a recording `effect` that
  logs each call's argument (in order) and returns `to_string(arg)`, then
  assert both the final value-outcome and the recorded call-trace match.

  Opts:
    * `:rule` (req), `:inputs` (req), `:allow_few_inputs`.
    * `:vars` — ordered *data* free-var names (excluding `effect`, which is
      appended last). Defaults to `[:list]`.
  """
  def assert_effect_trace_equivalent(before_expr, opts) do
    rule = Keyword.fetch!(opts, :rule)
    data_vars = opts |> Keyword.get(:vars, [:list]) |> List.wrap()
    inputs = Keyword.fetch!(opts, :inputs)

    fixed = precheck!(rule, before_expr, inputs, opts)

    vars = data_vars ++ [:effect]
    orig = compile_fn!(vars, before_expr)
    new = compile_fn!(vars, fixed)

    for input <- inputs do
      data_args = to_args(input, data_vars)
      {vo, trace_o} = run_with_trace(orig, data_args)
      {vn, trace_n} = run_with_trace(new, data_args)

      assert {vo, trace_o} === {vn, trace_n},
             """
             effect-trace divergence in #{inspect(rule)} on #{inspect(input)}
               original => value #{inspect(vo)}, trace #{inspect(trace_o)}
               fixed    => value #{inspect(vn)}, trace #{inspect(trace_n)}
               fixed code: #{String.trim(fixed)}
             """
    end

    :ok
  end

  # ── Opt-outs (auditable, reason mandatory) ────────────────────────────

  @doc "Mark a rule's fix as provably inert (no runtime behaviour to compare)."
  def mark_equivalence_cosmetic(reason) when is_binary(reason) and reason != "", do: :ok

  @doc """
  Mark a rule's fix as behavioural but with no self-contained callable example
  (cross-module / macro / compile-time). Weaker than cosmetic — keep this set
  small and reviewed.
  """
  def mark_equivalence_unconstructible(reason) when is_binary(reason) and reason != "", do: :ok

  @doc """
  Mark a rule as a **repair**: its firing precondition is that the input is
  *broken*, so there is no valid runtime behaviour to preserve and the fix is a
  *correction* rather than a behaviour-preserving rewrite. Two flavours:

    * **does-not-compile** — e.g. a hallucinated guard, a missing `require`. (The
      narrower `mark_equivalence_unconstructible/1` is the preferred wording for
      this flavour.)
    * **always-fails** — compiles, but raises on *every* possible input (e.g. an
      argument-order bug like piping a string into `Regex.replace/3`'s regex slot).

  Repair rules are deliberately NOT covered by the behaviour-preservation
  guarantee — that is sound, because the "before" has no input that produces a
  valid result. The reason MUST state the broken precondition (and, for
  always-fails, that *no* input avoids the crash) so the claim is auditable.
  Keep this set small and reviewed; a rule whose "before" returns a valid (even
  if undesired) value on some input is NOT a repair — it is a behaviour change
  and must be narrowed, gated, or dropped instead.
  """
  def mark_equivalence_repair(reason) when is_binary(reason) and reason != "", do: :ok

  # ── Outcome tagging ───────────────────────────────────────────────────

  @doc """
  Reduce an evaluation thunk to a comparable tagged outcome:
  `{:ok, value}` | `{:raise, module}` | `{:raise, module, message}` |
  `{:throw, term}` | `{:exit, term}`.
  """
  def eval_outcome(thunk, compare_messages? \\ false) when is_function(thunk, 0) do
    try do
      {:ok, thunk.()}
    rescue
      e ->
        if compare_messages?,
          do: {:raise, e.__struct__, Exception.message(e)},
          else: {:raise, e.__struct__}
    catch
      :throw, t -> {:throw, t}
      :exit, t -> {:exit, t}
    end
  end

  # ── internals ─────────────────────────────────────────────────────────

  defp precheck!(rule, source, inputs, opts) do
    assert rule_fires?(rule, source),
           "expected #{inspect(rule)} to fire on:\n#{source}"

    fixed = RuleHelpers.apply_rule_fix(rule, source)

    assert String.trim(fixed) != String.trim(source),
           "expected #{inspect(rule)} to rewrite the source, but it was unchanged:\n#{source}"

    unless Keyword.get(opts, :allow_few_inputs, false) do
      assert length(inputs) >= @min_inputs,
             "too few inputs: #{inspect(rule)} needs >= #{@min_inputs} inputs " <>
               "(got #{length(inputs)}); pass allow_few_inputs: true to override"
    end

    fixed
  end

  defp rule_fires?(rule, source) do
    ast = Sourceror.parse_string!(source)
    rule.check(ast, source: source) != []
  end

  defp compile_fn!(vars, expr) do
    arglist = Enum.join(vars, ", ")
    code = "fn #{arglist} -> (#{expr}) end"
    {fun, _binding} = silence(fn -> Code.eval_string(code) end)
    fun
  end

  defp compile_module!(source, tag) do
    [orig] = Regex.run(~r/defmodule\s+([A-Z][\w.]*)/, source, capture: :all_but_first)
    uniq = "Eqv_#{tag}_#{System.unique_integer([:positive])}"
    renamed = String.replace(source, "defmodule #{orig}", "defmodule #{uniq}", global: false)
    {{:module, mod, _bin, _val}, _binding} = silence(fn -> Code.eval_string(renamed) end)
    mod
  end

  defp run_with_trace(fun, data_args) do
    Process.put(:eqv_trace, [])

    effect = fn x ->
      Process.put(:eqv_trace, [x | Process.get(:eqv_trace)])
      to_string(x)
    end

    value = eval_outcome(fn -> apply(fun, data_args ++ [effect]) end)
    {value, Enum.reverse(Process.get(:eqv_trace))}
  end

  # No vars: a constant expression, called with no args (input is an ignored
  # placeholder). Single var: the input IS the sole argument. Multiple vars: a
  # tuple/list of args.
  defp to_args(_input, []), do: []

  defp to_args(input, vars) do
    cond do
      length(vars) == 1 -> [input]
      is_tuple(input) -> Tuple.to_list(input)
      is_list(input) -> input
      true -> [input]
    end
  end

  # Arity 1: the input IS the sole argument (even if it is itself a list).
  # Arity > 1: a tuple/list of positional args.
  defp args_by_arity(input, 1), do: [input]
  defp args_by_arity(input, _arity) when is_tuple(input), do: Tuple.to_list(input)
  defp args_by_arity(input, _arity) when is_list(input), do: input
  defp args_by_arity(input, _arity), do: [input]

  # Suppress compiler warnings (unused var, etc.) emitted during eval while
  # keeping the return value.
  defp silence(fun) do
    ExUnit.CaptureIO.capture_io(:stderr, fn -> send(self(), {:silenced, fun.()}) end)

    receive do
      {:silenced, result} -> result
    end
  end

  defp divergence_msg(rule, input, o, n, before, fixed) do
    """
    behaviour changed in #{inspect(rule)} on input #{inspect(input)}
      original => #{inspect(o)}
      fixed    => #{inspect(n)}
      before code: #{String.trim(before)}
      fixed code:  #{String.trim(fixed)}
    """
  end
end
