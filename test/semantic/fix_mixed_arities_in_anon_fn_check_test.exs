defmodule Credence.Semantic.FixMixedAritiesInAnonFnCheckTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2]

  alias Credence.Semantic.FixMixedAritiesInAnonFn

  @real_diag %{
    severity: :error,
    message: "cannot mix clauses with different arities in anonymous functions",
    position: {144, 50},
    file: "credence_check.ex",
    source: "credence_check.ex",
    span: nil
  }

  test "matches the diagnostic" do
    assert FixMixedAritiesInAnonFn.match?(@real_diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixMixedAritiesInAnonFn.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert FixMixedAritiesInAnonFn.to_issue(@real_diag).rule == :fix_mixed_arities_in_anon_fn
  end

  test "dispatches the compiler diagnostic through the semantic pipeline" do
    input = ~S"""
    defmodule MixedAritiesInAnonFnPipelineFixture do
      def build do
        fn :ok, y -> y; _ -> 0 end
      end
    end
    """

    {:error, diagnostics} = Credence.RuleHelpers.compile_and_capture(input)

    assert Enum.any?(diagnostics, fn diagnostic ->
             diagnostic.severity == :error and
               diagnostic.message ==
                 "cannot mix clauses with different arities in anonymous functions" and
               FixMixedAritiesInAnonFn.match?(diagnostic)
           end)

    expected = ~S"""
    defmodule MixedAritiesInAnonFnPipelineFixture do
      def build do
        fn
          :ok, y -> y
          _, _ -> 0
        end
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
    assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(expected)
  end
end
