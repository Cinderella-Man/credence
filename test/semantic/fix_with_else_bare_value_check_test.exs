defmodule Credence.Semantic.FixWithElseBareValueCheckTest do
  use ExUnit.Case

  alias Credence.RuleHelpers
  alias Credence.Semantic.FixWithElseBareValue

  # The string this rule shipped matching. Elixir 1.20.2 does not emit it, so
  # the rule was dead on arrival — and these tests passed anyway, because they
  # handed it the message it expected instead of one the compiler produced.
  # Kept as a match, because the project supports ~> 1.17 and some version
  # presumably said this; kept as a test, because it is the record of how a
  # rule and its tests can agree about a message that does not exist.
  @legacy_message ~s(expected -> clauses for :else in "with")

  test "matches the legacy diagnostic wording" do
    diag = %{severity: :error, message: @legacy_message, position: {59, 5}}
    assert FixWithElseBareValue.match?(diag)
  end

  # ═══════════════════════════════════════════════════════════════════
  # THE ONE THAT MATTERS — the message this toolchain really emits,
  # obtained by compiling rather than by writing it down.
  # ═══════════════════════════════════════════════════════════════════

  describe "the diagnostic the compiler actually emits" do
    setup do
      source = """
      defmodule WithElseRealDiagnostic do
        def run(x) do
          with {:ok, val} <- x do
            val
          else
            :error
          end
        end
      end
      """

      diagnostics =
        case RuleHelpers.compile_and_capture(source) do
          {:ok, ds} -> ds
          {:error, ds} -> ds
        end

      {:ok, source: source, diagnostics: diagnostics}
    end

    test "the fixture parses but does not compile", %{source: source} do
      assert Credence.RuleCase.valid_syntax?(source)
      refute Credence.RuleCase.compiles?(source)
    end

    test "the rule matches it", %{diagnostics: diagnostics} do
      assert Enum.any?(diagnostics, &FixWithElseBareValue.match?/1)
    end

    test "it is the `invalid \"else\" block` wording, not the legacy one", %{
      diagnostics: diagnostics
    } do
      matched = Enum.filter(diagnostics, &FixWithElseBareValue.match?/1)

      assert Enum.any?(matched, &(&1.message =~ ~s(invalid "else" block in "with")))
      refute Enum.any?(diagnostics, &(&1.message =~ @legacy_message))
    end

    test "no other live rule claims it", %{diagnostics: diagnostics} do
      # First-match-wins dispatch: a second claimant would decide which of the
      # two runs, and the loser would be dead exactly as this rule was.
      claimants =
        for d <- diagnostics,
            FixWithElseBareValue.match?(d),
            r <- Credence.Semantic.default_rules(),
            r != FixWithElseBareValue,
            r.match?(d),
            do: r

      assert claimants == []
    end

    test "it is repaired end-to-end through real dispatch", %{source: source} do
      result = Credence.fix(source)

      assert {FixWithElseBareValue, 1} in result.applied_rules
      assert result.code =~ "_ -> :error"
      assert Credence.RuleCase.compiles?(result.code)
    end
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}}
    refute FixWithElseBareValue.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "cannot compile module Foo (errors have been logged)",
      position: 0
    }

    refute FixWithElseBareValue.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @legacy_message, position: {59, 5}}
    assert FixWithElseBareValue.to_issue(diag).rule == :fix_with_else_bare_value
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @legacy_message, position: {42, 5}}
    assert FixWithElseBareValue.to_issue(diag).meta.line == 42
  end
end
