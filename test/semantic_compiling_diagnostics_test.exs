defmodule Credence.SemanticCompilingDiagnosticsTest do
  @moduledoc """
  T3.1 — the Semantic phase must see the error-severity diagnostics that a
  *successful* compile still reports.

  `Code.compile_string/2` runs `Module.ParallelChecker`, whose findings reach
  `Code.with_diagnostics/1`. Two of its checks — both struct checks in **pattern**
  position — are emitted at `severity: :error` even though the module compiles,
  so `RuleHelpers.compile_and_capture/1` returns `{:ok, [… severity: :error …]}`.
  The phase used to filter that branch to `severity == :warning`, which dropped
  the whole class before any rule's `match?/1` was consulted.

  The rule that shipped keyed on it — `Credence.Semantic.FixJasonDecodeErrorMessageField`,
  whose `@match_msg` is `"unknown key :message for struct Jason.DecodeError"` —
  is the reason this matters: its own tests call `match?/1` and `fix/2` directly,
  so it was green in CI and inert in production. It cannot be exercised here
  (`:jason` is not a dependency), so these tests use the same *class* with a
  locally-defined struct, and pin the pipeline rather than the rule.

  The probe rules are defined in this file on purpose: `RuleHelpers.discover_rules/1`
  reads `Application.spec(:credence, :modules)`, which covers `lib` and
  `test/support` but never a `_test.exs` file — so they can only ever run when
  handed in explicitly via `:semantic_rules`, and cannot leak into the live set.
  """
  use ExUnit.Case, async: true

  alias Credence.RuleHelpers
  alias Credence.Semantic

  # --- probe rules ------------------------------------------------------------

  defmodule UnknownStructKeyProbe do
    @moduledoc false
    use Credence.Semantic.Rule

    @impl true
    def match?(%{severity: :error, message: msg}) when is_binary(msg),
      do: String.starts_with?(msg, "unknown key :size for struct")

    def match?(_), do: false

    @impl true
    def to_issue(diagnostic),
      do: %Credence.Issue{
        rule: :unknown_struct_key_probe,
        message: diagnostic.message,
        meta: %{line: 1}
      }

    @impl true
    def fix(source, _diagnostic) do
      String.replace(
        source,
        "def take(%Probe31A{path: p, size: s}), do: {p, s}",
        "def take(%Probe31A{path: p}), do: {p, nil}"
      )
    end
  end

  # Matches an ordinary warning, and its "fix" introduces a pattern-position
  # struct error while leaving the source compiling — the exact shape
  # `health_from/2`'s `{:ok, …}` clause was blind to.
  defmodule SneaksInATypeErrorProbe do
    @moduledoc false
    use Credence.Semantic.Rule

    @impl true
    def match?(%{severity: :warning, message: msg}) when is_binary(msg),
      do: String.contains?(msg, "is unused")

    def match?(_), do: false

    @impl true
    def to_issue(d), do: %Credence.Issue{rule: :sneaks_in_probe, message: d.message, meta: %{}}

    @impl true
    def fix(source, _diagnostic),
      do: String.replace(source, "def take(%Probe31B{path: p})", "def take(%Probe31B{nope: p})")
  end

  # --- fixtures ---------------------------------------------------------------

  # Compiles cleanly, but `:size` is not a key of the struct and the reference is
  # in a *pattern*, so the checker reports it at `:error`.
  @error_on_compiling_source """
  defmodule Probe31A do
    defstruct [:path]
  end

  defmodule Probe31AUser do
    def take(%Probe31A{path: p, size: s}), do: {p, s}
  end
  """

  @unused_variable_source """
  defmodule Probe31B do
    defstruct [:path]
  end

  defmodule Probe31BUser do
    def take(%Probe31B{path: p}), do: :ok
  end
  """

  describe "the premise these tests rest on" do
    test "a compiling source really does report an error-severity diagnostic" do
      assert {:ok, diagnostics} = RuleHelpers.compile_and_capture(@error_on_compiling_source)

      errors = Enum.filter(diagnostics, &(&1.severity == :error))

      assert errors != [],
             "compile_and_capture/1 returned {:ok, …} with no error-severity diagnostic, so " <>
               "every test below is vacuous. Either Elixir stopped raising the pattern-position " <>
               "struct checks to :error, or the fixture stopped triggering them."

      assert Enum.any?(errors, &String.starts_with?(&1.message, "unknown key :size for struct")),
             "expected the pattern-position unknown-key diagnostic, got: " <>
               inspect(Enum.map(errors, & &1.message))
    end
  end

  describe "analyze/2 on a source that compiles" do
    test "routes an error-severity diagnostic to the rule that matches it" do
      issues =
        Semantic.analyze(@error_on_compiling_source, semantic_rules: [UnknownStructKeyProbe])

      assert [%Credence.Issue{rule: :unknown_struct_key_probe}] = issues
    end

    test "still routes warnings" do
      issues =
        Semantic.analyze(@unused_variable_source, semantic_rules: [SneaksInATypeErrorProbe])

      assert [%Credence.Issue{rule: :sneaks_in_probe}] = issues
    end
  end

  describe "fix_with_trace/2 on a source that compiles" do
    test "applies a fix for an error-severity diagnostic" do
      {fixed, applied} =
        Semantic.fix_with_trace(@error_on_compiling_source,
          semantic_rules: [UnknownStructKeyProbe]
        )

      assert applied == [{UnknownStructKeyProbe, 1}]
      refute fixed == @error_on_compiling_source

      assert {:ok, diagnostics} = RuleHelpers.compile_and_capture(fixed)
      assert Enum.filter(diagnostics, &(&1.severity == :error)) == []
    end

    test "reverts a fix that adds a type error to source that still compiles" do
      {fixed, applied} =
        Semantic.fix_with_trace(@unused_variable_source,
          semantic_rules: [SneaksInATypeErrorProbe]
        )

      assert applied == [{SneaksInATypeErrorProbe, :reverted}],
             "a fix that keeps the source compiling but introduces an error-severity type " <>
               "diagnostic must be reverted. Before T3.1, health_from/2's {:ok, …} clause " <>
               "hardcoded `errors: %{}`, so verdict/2 could only ever return :ok on this " <>
               "branch and the whole warning pass ran with no gate behind it."

      assert fixed == @unused_variable_source
    end
  end
end
