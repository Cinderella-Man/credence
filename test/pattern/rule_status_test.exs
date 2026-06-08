defmodule Credence.Pattern.RuleStatusTest do
  @moduledoc "Coverage for `rule_status/1` and `enabled_rules/1` (decision 10)."
  use ExUnit.Case

  alias Credence.Pattern

  setup do
    Application.delete_env(:credence, :assumptions)
    on_exit(fn -> Application.delete_env(:credence, :assumptions) end)
    :ok
  end

  defp status_for(name, opts) do
    opts |> Pattern.rule_status() |> Enum.find(&(&1.name == name))
  end

  test "lists every discovered rule" do
    assert length(Pattern.rule_status()) == length(Pattern.default_rules())
  end

  test "a no-promise rule is always enabled with no missing promises" do
    s = status_for("NoManualStringReverse", [])
    assert s.assumptions == []
    assert s.enabled
    assert s.missing == []

    # still enabled under strict
    assert status_for("NoManualStringReverse", assumptions: :strict).enabled
  end

  test "a switched rule is enabled by default, off when its promise is off" do
    default = status_for("AvoidGraphemesEnumCountWithPredicate", [])
    assert default.assumptions == [:single_codepoint_graphemes]
    assert default.enabled
    assert default.missing == []

    off = status_for("AvoidGraphemesEnumCountWithPredicate", assumptions: :strict)
    refute off.enabled
    assert off.missing == [:single_codepoint_graphemes]
  end

  test "enabled_rules/1 is the on-names from rule_status/1" do
    expected =
      Pattern.rule_status(assumptions: :strict)
      |> Enum.filter(& &1.enabled)
      |> Enum.map(& &1.name)

    assert Pattern.enabled_rules(assumptions: :strict) == expected
    refute "NoCodepointStringReverse" in Pattern.enabled_rules(assumptions: :strict)
  end
end
