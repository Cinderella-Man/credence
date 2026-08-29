defmodule Credence.SyntaxPipelineTest do
  use ExUnit.Case, async: false

  defmodule RaisingRule do
    def fix(_source), do: raise("fixture raise")
  end

  defmodule ExitingRule do
    def fix(_source), do: exit(:fixture_exit)
  end

  defmodule NonStringRule do
    def fix(_source), do: :not_source
  end

  defmodule RepairingRule do
    def fix(_source), do: "value = :repaired\n"
  end

  test "a defective syntax fix is recorded and later rules still repair the source" do
    for defective_rule <- [RaisingRule, ExitingRule, NonStringRule] do
      assert Credence.Syntax.fix_with_trace("broken(",
               syntax_rules: [defective_rule, RepairingRule]
             ) == {"value = :repaired\n", [{defective_rule, :crashed}, {RepairingRule, 1}]}
    end
  end

  test "an exact syntax rule list does not discover default rules" do
    mfa = {Credence.Syntax, :default_rules, 0}
    :erlang.trace_pattern(mfa, true, [:call_count])

    on_exit(fn -> :erlang.trace_pattern(mfa, false, [:call_count]) end)

    assert Credence.Syntax.fix_with_trace("broken(", syntax_rules: []) == {"broken(", []}
    assert :erlang.trace_info(mfa, :call_count) == {:call_count, 0}
  end
end
