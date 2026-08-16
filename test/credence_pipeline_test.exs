defmodule Credence.PipelineTest do
  @moduledoc """
  Integration tests for the Credence fix pipeline.

  Validates the interaction between all three phases (Syntax → Semantic → Pattern),
  compile-gating behavior, BEAM safety during module cleanup, and invariants
  like idempotency and "fix must not break compiling code."

  These tests exercise the real rule set — they are NOT mocked.
  Module names use the `CrdPT_*` prefix to avoid collisions with
  application modules or other tests.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  # ── Helpers ──────────────────────────────────────────────────────────

  defp pattern_rules(applied), do: rules_in_phase(applied, "Pattern")
  defp semantic_rules(applied), do: rules_in_phase(applied, "Semantic")

  defp rules_in_phase(applied_rules, phase) do
    Enum.filter(applied_rules, fn {mod, _count} ->
      phase in Module.split(mod)
    end)
  end

  defp has_pattern_rules?(applied), do: pattern_rules(applied) != []
  defp has_semantic_rules?(applied), do: semantic_rules(applied) != []

  defp code_compiles?(code) do
    {result, _diagnostics} =
      Code.with_diagnostics(fn ->
        try do
          modules = Code.compile_string(code, "pipeline_test_check.ex")

          for {mod, _bin} <- modules do
            :code.soft_purge(mod)
            :code.delete(mod)
            :code.soft_purge(mod)
          end

          :ok
        rescue
          _ -> :error
        end
      end)

    result == :ok
  end

  defp code_parses?(code) do
    match?({:ok, _}, Sourceror.parse_string(code))
  end

  defp cleanup_module(mod) do
    :code.soft_purge(mod)
    :code.delete(mod)
    :code.soft_purge(mod)
  end

  # Call a function on a module that was compiled at runtime.
  # Using a variable avoids the compile-time "module is not available" warning.
  defp dynamic_call(mod, fun, args \\ []) do
    apply(mod, fun, args)
  end

  # ── 1. Positive cases — fixes applied across phases ─────────────────

  describe "positive: semantic fixes" do
    test "prefixes unused variable with underscore" do
      source = ~S"""
      defmodule CrdPT_UnusedVar do
        def example do
          unused = 1
          :ok
        end
      end
      """

      result = Credence.fix(source)

      expected = ~S"""
      defmodule CrdPT_UnusedVar do
        def example do
          :ok
        end
      end
      """

      assert result.code == expected
      assert has_semantic_rules?(result.applied_rules)
      assert code_compiles?(result.code)
    end

    test "removes underscore from used variable" do
      source = ~S"""
      defmodule CrdPT_UsedUnderscore do
        def example do
          _count = Enum.count([1, 2, 3])
          _count + 1
        end
      end
      """

      result = Credence.fix(source)

      # _count used on two lines → should become count
      expected = ~S"""
      defmodule CrdPT_UsedUnderscore do
        def example do
          count = length([1, 2, 3])
          count + 1
        end
      end
      """

      assert result.code == expected
      assert has_semantic_rules?(result.applied_rules)
      assert code_compiles?(result.code)
    end
  end

  describe "positive: pattern fixes" do
    test "replaces Enum.reduce sum with Enum.sum" do
      source = ~S"""
      defmodule CrdPT_SumReduce do
        @doc "Sums a list."
        @spec total([number()]) :: number()
        def total(list) do
          Enum.reduce(list, 0, fn x, acc -> acc + x end)
        end
      end
      """

      result = Credence.fix(source)

      expected = ~S"""
      defmodule CrdPT_SumReduce do
        @doc "Sums a list."
        @spec total([number()]) :: number()
        def total(list) do
          Enum.sum(list)
        end
      end
      """

      assert result.code == expected
      assert has_pattern_rules?(result.applied_rules)
      assert code_compiles?(result.code)
    end
  end

  describe "positive: multi-phase fixes" do
    test "applies both semantic and pattern fixes in one pass" do
      source = ~S"""
      defmodule CrdPT_MultiPhase do
        @doc "Sums a list."
        @spec total([number()]) :: number()
        def total(list) do
          unused = :ignored
          Enum.reduce(list, 0, fn x, acc -> acc + x end)
        end
      end
      """

      result = Credence.fix(source)

      # Semantic: unused → _unused; Pattern: Enum.reduce → Enum.sum
      expected = ~S"""
      defmodule CrdPT_MultiPhase do
        @doc "Sums a list."
        @spec total([number()]) :: number()
        def total(list) do
          Enum.sum(list)
        end
      end
      """

      assert result.code == expected
      assert has_semantic_rules?(result.applied_rules)
      assert has_pattern_rules?(result.applied_rules)
      assert code_compiles?(result.code)
    end
  end

  describe "positive: clean code" do
    test "returns no applied rules for code that needs no fixes" do
      source = ~S"""
      defmodule CrdPT_Clean do
        @doc "Adds two numbers."
        @spec add(integer(), integer()) :: integer()
        def add(a, b), do: a + b
      end
      """

      result = Credence.fix(source)

      assert result.applied_rules == []
    end
  end

  # ── 2. Pattern phase gating on compilation status ───────────────────

  describe "pattern gating: a file that does not compile is still fixed" do
    # These four tests used to assert the opposite — that the Pattern round was
    # skipped entirely on non-compiling source. The reason given was that
    # "applying AST transforms on semantically broken code risks making it
    # worse". That risk is real; skipping 156 rules was the wrong answer to it.
    #
    # Measured before changing anything: 625 of 1,724 Pattern test fixtures parse
    # but do not compile, and 292 of those have a Pattern rule firing that never
    # ran. `&even?/1` with nothing defining `even?` is enough to disable the
    # whole round, and that is what LLM output looks like mid-generation — the
    # input Credence exists for.
    #
    # The risk is now handled where it belongs, per fix rather than per file:
    # `RuleHelpers.compiles_no_worse?/2` reverts any fix that ADDS a compile
    # error. What is kept is the guarantee ("we never make it worse"); what is
    # dropped is the blunt instrument.
    #
    # Checked before relying on it: the Elixir compiler COLLECTS errors rather
    # than stopping at the first, so a pre-existing error does not mask one a fix
    # introduces. A module with two undefined variables reports both.
    test "fixes the anti-pattern when code has an undefined variable" do
      source = ~S"""
      defmodule CrdPT_UndefVar do
        def foo(list) do
          x = undefined_var + 1
          Enum.reduce(list, 0, fn el, acc -> acc + el end)
        end
      end
      """

      assert code_parses?(source), "precondition: source must parse"
      refute code_compiles?(source), "precondition: source must NOT compile"

      result = Credence.fix(source)

      assert has_pattern_rules?(result.applied_rules)
      assert result.code =~ "Enum.sum(list)"

      # And the pre-existing breakage is still there, untouched: the round
      # repaired the idiom it understands and invented nothing.
      assert result.code =~ "undefined_var"
      refute code_compiles?(result.code)
    end

    test "fixes the anti-pattern when code has several undefined variables" do
      source = ~S"""
      defmodule CrdPT_MultiUndef do
        def bar(list) do
          result = undefined_a + undefined_b
          Enum.reduce(list, 0, fn x, acc -> acc + x end)
        end
      end
      """

      assert code_parses?(source)
      refute code_compiles?(source)

      result = Credence.fix(source)

      assert has_pattern_rules?(result.applied_rules)
      assert result.code =~ "Enum.sum(list)"
    end

    test "fixes the anti-pattern when code has a guard error" do
      source = ~S"""
      defmodule CrdPT_BadGuard do
        def check(x) when custom_guard(x) do
          Enum.reduce([x], 0, fn el, acc -> acc + el end)
        end
      end
      """

      assert code_parses?(source)
      refute code_compiles?(source)

      assert has_pattern_rules?(Credence.fix(source).applied_rules)
    end

    test "Pattern.fix_with_trace still returns unchanged source when no rule fires" do
      # Nothing here is an anti-pattern, so the round finding nothing is the
      # right answer — but now for the right reason. Under the old gate this
      # passed on ANY non-compiling input, which made it indistinguishable from
      # a test of the skip itself.
      source = ~S"""
      defmodule CrdPT_PatternDirect do
        def broken do
          undefined_variable
        end
      end
      """

      refute code_compiles?(source)

      {result_code, applied} = Credence.Pattern.fix_with_trace(source)

      assert result_code == source
      assert applied == []
    end

    test "pattern runs normally when code compiles with warnings" do
      # Unused variable is a WARNING, not an error — code still compiles.
      # Pattern must still run.
      source = ~S"""
      defmodule CrdPT_CompilesWithWarning do
        @doc "Sums a list."
        @spec total([number()]) :: number()
        def total(list) do
          _ignored = :ok
          Enum.reduce(list, 0, fn x, acc -> acc + x end)
        end
      end
      """

      assert code_compiles?(source), "precondition: code must compile (warning is not failure)"

      result = Credence.fix(source)

      expected = ~S"""
      defmodule CrdPT_CompilesWithWarning do
        @doc "Sums a list."
        @spec total([number()]) :: number()
        def total(list) do
          Enum.sum(list)
        end
      end
      """

      assert result.code == expected
      assert has_pattern_rules?(result.applied_rules)
    end

    test "logs the pre-existing errors a fix is not allowed to add to" do
      source = ~S"""
      defmodule CrdPT_SkipLog do
        def broken, do: undefined_var
      end
      """

      previous_level = Logger.level()
      Logger.configure(level: :debug)

      log = capture_log(fn -> Credence.Pattern.fix_with_trace(source) end)

      Logger.configure(level: previous_level)

      assert log =~ "pre-existing compile error",
             "expected the round to announce the baseline it is holding fixes to, got:\n#{log}"
    end
  end

  # ── Compile-output gate ───────────────────────────────────────────
  #
  # If a rule's `fix/2` returns source that no longer compiles, the
  # pipeline must revert to the pre-fix source and surface the rule
  # as `:reverted` in the trace — never silently propagate broken
  # output to the next rule or to the caller.

  defmodule BrokenFixRule do
    @moduledoc false
    use Credence.Pattern.Rule

    @impl true
    def priority, do: 100

    @impl true
    def check(_ast, _opts) do
      [%Credence.Issue{rule: :broken_fix, message: "broken", meta: %{line: 1}}]
    end

    @impl true
    def fix_patches(_ast, opts) do
      source = Keyword.fetch!(opts, :source)
      # Parses but does not compile (undefined function).
      broken_source =
        "defmodule Broken_NotARealMod_xyz do\n  def go, do: some_undefined_thing()\nend\n"

      [whole_source_patch(source, broken_source)]
    end

    defp whole_source_patch(source, replacement) do
      lines = String.split(source, "\n")
      end_line = max(length(lines), 1)
      end_col = (lines |> List.last() |> byte_size()) + 1

      %{
        range: %{start: [line: 1, column: 1], end: [line: end_line, column: end_col]},
        change: replacement
      }
    end
  end

  defmodule UnparseableFixRule do
    @moduledoc false
    use Credence.Pattern.Rule

    @impl true
    def priority, do: 100

    @impl true
    def check(_ast, _opts) do
      [%Credence.Issue{rule: :unparseable_fix, message: "x", meta: %{line: 1}}]
    end

    @impl true
    def fix_patches(_ast, opts) do
      source = Keyword.fetch!(opts, :source)
      lines = String.split(source, "\n")
      end_line = max(length(lines), 1)
      end_col = (lines |> List.last() |> byte_size()) + 1

      [
        %{
          range: %{start: [line: 1, column: 1], end: [line: end_line, column: end_col]},
          change: "this is <<< not valid elixir at all"
        }
      ]
    end
  end

  describe "compile-output gate" do
    test "reverts a rule whose output does not compile" do
      input = ~S"""
      defmodule CrdPT_RevertTarget do
        def go, do: :ok
      end
      """

      # `with_log/1` keeps the (intentional) revert warning out of test
      # output. The dedicated `logs a warning ...` test below asserts
      # the warning's content.
      {{output, applied}, _log} =
        ExUnit.CaptureLog.with_log(fn ->
          Credence.Pattern.fix_with_trace(input, rules: [BrokenFixRule])
        end)

      assert output == input
      assert applied == [{BrokenFixRule, :reverted}]
    end

    test "reverts a rule whose output does not even parse" do
      input = ~S"""
      defmodule CrdPT_UnparseableTarget do
        def go, do: :ok
      end
      """

      {{output, applied}, _log} =
        ExUnit.CaptureLog.with_log(fn ->
          Credence.Pattern.fix_with_trace(input, rules: [UnparseableFixRule])
        end)

      assert output == input
      assert applied == [{UnparseableFixRule, :reverted}]
    end

    test "logs a warning identifying the offending rule" do
      input = ~S"""
      defmodule CrdPT_RevertLog do
        def go, do: :ok
      end
      """

      log =
        capture_log(fn ->
          Credence.Pattern.fix_with_trace(input, rules: [BrokenFixRule])
        end)

      assert log =~ "BrokenFixRule"
      assert log =~ "non-compiling" or log =~ "reverting"
    end

    test "a reverted rule does not poison the rest of the pipeline" do
      # Run the broken rule alongside the real rule set. The broken rule
      # should revert; the real rules should still operate on the
      # original (compiling) input afterwards.
      input = ~S"""
      defmodule CrdPT_RevertIsolation do
        def go(list) do
          length(list) == 0
        end
      end
      """

      rules = [BrokenFixRule | Credence.Pattern.default_rules()]

      {{output, applied}, _log} =
        ExUnit.CaptureLog.with_log(fn ->
          Credence.Pattern.fix_with_trace(input, rules: rules)
        end)

      # Broken rule reverted, other rules still applied.
      assert {BrokenFixRule, :reverted} in applied
      assert code_compiles?(output)

      # The real rule for length == 0 should have fired and produced
      # `list == []` in the output.
      expected = ~S"""
      defmodule CrdPT_RevertIsolation do
        def go(list) do
          list == []
        end
      end
      """

      assert output == expected
    end
  end

  describe "pattern gating: pattern runs after semantic fixes resolve compilation" do
    test "semantic fixes warning, code was already compiling, pattern fires" do
      # _result is used → UsedUnderscoreVariable fires (warning-level).
      # Code compiles throughout, so pattern should fire too.
      source = ~S"""
      defmodule CrdPT_SemThenPat do
        @doc "Sums a list."
        @spec total([number()]) :: number()
        def total(list) do
          _result = Enum.reduce(list, 0, fn x, acc -> acc + x end)
          _result
        end
      end
      """

      assert code_compiles?(source)

      result = Credence.fix(source)

      assert has_semantic_rules?(result.applied_rules),
             "semantic should have fixed _result → result"

      assert has_pattern_rules?(result.applied_rules),
             "pattern should have fired on compiling code"
    end
  end

  # ── 3. BEAM safety — module cleanup ─────────────────────────────────

  describe "BEAM safety: soft_purge prevents crashes" do
    test "analyze does not crash when source redefines an already-loaded module" do
      # Pre-load a module into the BEAM
      [{mod, _bin}] =
        Code.compile_string("""
        defmodule CrdPT_Redefine_A do
          def hello, do: :world
        end
        """)

      assert dynamic_call(mod, :hello) == :world

      # Analyze source that defines the SAME module name.
      # Semantic's compile_and_capture will compile this, then clean up.
      # With hard :code.purge this kills the BEAM; with soft_purge it's safe.
      # The module gets cleaned up (no process is running it), which is fine —
      # the important thing is the process survives.
      source = ~S"""
      defmodule CrdPT_Redefine_A do
        def hello, do: :world
      end
      """

      result = Credence.analyze(source)

      assert is_map(result)
      assert Map.has_key?(result, :valid)
      assert Map.has_key?(result, :issues)
    after
      cleanup_module(CrdPT_Redefine_A)
    end

    test "fix does not crash when source redefines an already-loaded module" do
      [{_mod, _bin}] =
        Code.compile_string("""
        defmodule CrdPT_Redefine_B do
          def greet, do: :hi
        end
        """)

      source = ~S"""
      defmodule CrdPT_Redefine_B do
        def greet do
          unused = 1
          :hi
        end
      end
      """

      result = Credence.fix(source)

      assert is_map(result)
      assert Map.has_key?(result, :code)
    after
      cleanup_module(CrdPT_Redefine_B)
    end

    test "does not crash when analyzed source defines a module on the call stack" do
      # This is the critical reproduction of the reported BEAM-kill bug:
      # we call analyze FROM a module that the analyzed source redefines.
      # The module IS on the call stack, so soft_purge leaves it alive.
      [{mod, _bin}] =
        Code.compile_string(~S"""
        defmodule CrdPT_CallStack do
          def run do
            source = "defmodule CrdPT_CallStack do\n  def run, do: :ok\nend"
            Credence.Semantic.analyze(source)
          end
        end
        """)

      # CrdPT_CallStack.run/0 is on the call stack when Semantic compiles
      # source that redefines CrdPT_CallStack. With :code.purge this kills
      # the BEAM. With :code.soft_purge the process survives.
      result = dynamic_call(mod, :run)
      assert is_list(result)
    after
      cleanup_module(CrdPT_CallStack)
    end

    test "Semantic.fix_with_trace survives redefining a loaded module" do
      [{_mod, _bin}] =
        Code.compile_string("""
        defmodule CrdPT_Redefine_C do
          def value, do: 42
        end
        """)

      source = ~S"""
      defmodule CrdPT_Redefine_C do
        def value do
          unused = 1
          42
        end
      end
      """

      {fixed, _applied} = Credence.Semantic.fix_with_trace(source)

      assert is_binary(fixed)
    after
      cleanup_module(CrdPT_Redefine_C)
    end

    test "Pattern compile-check survives redefining a loaded module" do
      [{_mod, _bin}] =
        Code.compile_string("""
        defmodule CrdPT_Redefine_D do
          def value, do: :ok
        end
        """)

      source = ~S"""
      defmodule CrdPT_Redefine_D do
        @doc "Returns ok."
        @spec value() :: :ok
        def value, do: :ok
      end
      """

      {fixed, _applied} = Credence.Pattern.fix_with_trace(source)

      assert is_binary(fixed)
    after
      cleanup_module(CrdPT_Redefine_D)
    end
  end

  # ── 4. Invariants ───────────────────────────────────────────────────

  describe "invariant: fix never breaks compiling code" do
    test "output compiles when input compiles (simple case)" do
      source = ~S"""
      defmodule CrdPT_Invariant1 do
        def example(list) do
          unused = :ok
          Enum.reduce(list, 0, fn x, acc -> acc + x end)
        end
      end
      """

      assert code_compiles?(source), "precondition"

      result = Credence.fix(source)

      assert code_compiles?(result.code),
             "fix must not break compiling code. Output:\n#{result.code}"
    end

    test "output compiles when input compiles (multiple function clauses)" do
      source = ~S"""
      defmodule CrdPT_Invariant2 do
        @doc "Sums non-negative integers."
        @spec safe_sum([integer()]) :: integer()
        def safe_sum([]), do: 0

        def safe_sum(list) do
          Enum.reduce(list, 0, fn x, acc -> acc + x end)
        end
      end
      """

      assert code_compiles?(source)

      result = Credence.fix(source)

      assert code_compiles?(result.code),
             "fix must not break compiling code. Output:\n#{result.code}"
    end

    test "output compiles when input compiles (pattern match heavy)" do
      source = ~S"""
      defmodule CrdPT_Invariant3 do
        def process(%{items: items, mode: mode}) do
          unused_debug = :verbose
          count = length(items)
          result = Enum.reduce(items, 0, fn x, acc -> acc + x end)
          {mode, count, result}
        end
      end
      """

      assert code_compiles?(source)

      result = Credence.fix(source)

      assert code_compiles?(result.code),
             "fix must not break compiling code. Output:\n#{result.code}"
    end
  end

  describe "invariant: fix is idempotent" do
    test "applying fix twice produces the same output" do
      source = ~S"""
      defmodule CrdPT_Idempotent do
        def total(list) do
          unused = 1
          Enum.reduce(list, 0, fn x, acc -> acc + x end)
        end
      end
      """

      first = Credence.fix(source)
      second = Credence.fix(first.code)

      assert first.code == second.code,
             "fix is not idempotent.\nFirst:\n#{first.code}\nSecond:\n#{second.code}"

      assert second.applied_rules == [],
             "second pass should find nothing to fix, but applied: #{inspect(second.applied_rules)}"
    end
  end

  # ── 5. Phase ordering and edge cases ────────────────────────────────

  describe "phase ordering" do
    test "syntax phase runs before semantic (non-parseable code)" do
      # If code doesn't parse, semantic and pattern shouldn't blow up.
      # Syntax gets first crack. If it can't fix parsing, the other phases
      # receive the still-broken source and should handle it gracefully.
      source = ~S"""
      defmodule CrdPT_SyntaxFirst do
        def broken(
          :ok
        end
      end
      """

      refute code_parses?(source), "precondition: source must not parse"

      # Must not raise — even if no syntax rule can fix it,
      # the pipeline should return gracefully.
      result = Credence.fix(source)
      assert is_map(result)
      assert is_binary(result.code)
    end

    test "all three phases are represented in applied_rules when all fire" do
      # We need source where syntax, semantic, AND pattern all fire.
      # Syntax only fires when code doesn't parse, which is mutually
      # exclusive with semantic/pattern (those need parseable code).
      # So in practice, a single source can trigger at most TWO phases
      # (semantic + pattern). This test documents that expectation.
      source = ~S"""
      defmodule CrdPT_TwoPhases do
        @doc "Sums a list."
        @spec total([number()]) :: number()
        def total(list) do
          unused = :ok
          Enum.reduce(list, 0, fn x, acc -> acc + x end)
        end
      end
      """

      result = Credence.fix(source)

      assert has_semantic_rules?(result.applied_rules)
      assert has_pattern_rules?(result.applied_rules)
    end
  end

  describe "edge cases" do
    test "empty source" do
      result = Credence.fix("")
      assert is_map(result)
      assert result.code == "" or is_binary(result.code)
    end

    test "source with only comments" do
      source = ~S"""
      # This is just a comment
      # No module defined
      """

      result = Credence.fix(source)
      assert is_map(result)
    end

    test "source with multiple modules" do
      source = ~S"""
      defmodule CrdPT_Multi_A do
        def a, do: 1
      end

      defmodule CrdPT_Multi_B do
        def b do
          unused = 2
          :ok
        end
      end
      """

      result = Credence.fix(source)

      assert code_compiles?(result.code)

      # Semantic should fix the unused var in Multi_B
      expected = ~S"""
      defmodule CrdPT_Multi_A do
        def a, do: 1
      end

      defmodule CrdPT_Multi_B do
        def b do
          :ok
        end
      end
      """

      assert result.code == expected
    end

    test "compile error with zero diagnostics (rescue path)" do
      # Some code causes Code.compile_string to raise an exception
      # rather than producing diagnostics. The pipeline should handle
      # this gracefully and not crash.
      #
      # This is the "compilation FAILED, 0 error(s)" case seen in logs.
      # Exact triggers depend on Elixir version; we just verify the
      # pipeline doesn't blow up on exotic code.
      source = ~S"""
      defmodule CrdPT_ExoticError do
        defmacro __using__(_opts) do
          quote do
            undefined_compile_time_var!()
          end
        end
      end
      """

      # Regardless of whether this compiles, fix must not raise
      result = Credence.fix(source)
      assert is_map(result)
      assert is_binary(result.code)
    end

    test "pattern fix_with_trace is safe when source cannot even be parsed" do
      source = "defmodule Broken do def( end"

      refute code_parses?(source)

      # Pattern's fix_with_trace has a Sourceror.parse_string guard in
      # its reduce — it should bail gracefully.
      {result_code, applied} = Credence.Pattern.fix_with_trace(source)

      assert result_code == source
      assert applied == []
    end
  end

  # ── 6. Logging verification ─────────────────────────────────────────

  describe "logging" do
    setup do
      previous_level = Logger.level()
      Logger.configure(level: :debug)
      on_exit(fn -> Logger.configure(level: previous_level) end)
      :ok
    end

    test "logs full diff without truncation" do
      # Validates that the log_diff fix is in place — no "... (N more changes)"
      source = ~S"""
      defmodule CrdPT_DiffLog do
        @doc "Sums a list."
        @spec total([number()]) :: number()
        def total(list) do
          Enum.reduce(list, 0, fn x, acc -> acc + x end)
        end
      end
      """

      log =
        capture_log(fn ->
          Credence.fix(source)
        end)

      refute log =~ "more changes)",
             "diff should not be truncated — found truncation marker in log"
    end

    test "semantic fix pipeline logs pass number and compilation result" do
      source = ~S"""
      defmodule CrdPT_SemLog do
        def example do
          unused = 1
          :ok
        end
      end
      """

      log =
        capture_log(fn ->
          Credence.Semantic.fix_with_trace(source)
        end)

      assert log =~ "starting semantic fix pipeline"
      assert log =~ "semantic pass 1"
      assert log =~ "semantic done"
    end

    test "syntax fix pipeline logs skip when source already parses" do
      source = ~S"""
      defmodule CrdPT_SynLog do
        def ok, do: :ok
      end
      """

      log =
        capture_log(fn ->
          Credence.Syntax.fix_with_trace(source)
        end)

      assert log =~ "source already parses"
    end
  end
end
