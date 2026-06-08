defmodule Credence.Pattern.AssumptionsFilteringTest do
  @moduledoc """
  End-to-end coverage of the switch filter through the real public API
  (`Credence.fix/2`, `Credence.analyze/2`, `Credence.Pattern`). Checks decisions
  2, 6, 7, 8, 9 and 11.
  """
  use ExUnit.Case
  import ExUnit.CaptureLog

  # A module whose only fixable pattern is the switched with-predicate rule.
  @switched """
  defmodule Example do
    def f(str), do: Enum.count(String.graphemes(str), &(&1 == "1"))
  end
  """

  # The @switched module after the switched rule runs.
  @switched_fixed """
  defmodule Example do
    def f(str), do: String.count(str, "1")
  end
  """

  defp fix(code, opts \\ []), do: Credence.fix(code, opts).code

  defp issue_rules(code, opts \\ []),
    do: Credence.analyze(code, opts).issues |> Enum.map(& &1.rule)

  setup do
    # Each test starts from a clean config slate.
    Application.delete_env(:credence, :assumptions)
    on_exit(fn -> Application.delete_env(:credence, :assumptions) end)
    :ok
  end

  describe "default (helpful) mode" do
    test "a switched rule runs: the pattern is reported and fixed" do
      assert :avoid_graphemes_enum_count_with_predicate in issue_rules(@switched)
      assert fix(@switched) == @switched_fixed
    end
  end

  describe "switch turned off" do
    test "no issue is reported and fix leaves the code untouched" do
      opts = [assumptions: %{single_codepoint_graphemes: false}]
      refute :avoid_graphemes_enum_count_with_predicate in issue_rules(@switched, opts)
      assert fix(@switched, opts) == @switched
    end
  end

  describe ":strict mode" do
    test "only no-promise rules run; the switched rules are off" do
      enabled = Credence.Pattern.enabled_rules(assumptions: :strict)

      refute "AvoidGraphemesEnumCountWithPredicate" in enabled
      refute "NoCodepointStringReverse" in enabled
      # an always-safe rule is unaffected
      assert "NoManualStringReverse" in enabled
    end

    test "the switched code is left untouched in :strict" do
      assert fix(@switched, assumptions: :strict) == @switched
    end
  end

  describe ":default re-enables under a :strict project config" do
    test "config :strict turns it off; a call passing :default turns it back on" do
      Application.put_env(:credence, :assumptions, :strict)

      assert fix(@switched) == @switched
      assert fix(@switched, assumptions: :default) == @switched_fixed
    end
  end

  describe "three places, later wins" do
    test "config is respected and call options override it" do
      Application.put_env(:credence, :assumptions, :strict)

      # config alone → off
      assert fix(@switched) == @switched

      # call re-enables just this switch for this run
      assert fix(@switched, assumptions: %{single_codepoint_graphemes: true}) ==
               @switched_fixed
    end

    test "a missing config place does nothing (default behaviour)" do
      # no config set in this test
      assert fix(@switched) == @switched_fixed
    end
  end

  describe "errors and warnings" do
    test "an unknown switch name you pass stops with a clear error" do
      assert_raise ArgumentError, ~r/unknown assumption/, fn ->
        Credence.analyze(@switched, assumptions: %{bogus: true})
      end
    end

    test "naming a filtered rule in an explicit rules: list warns but stays filtered" do
      code = """
      defmodule Example do
        def f(str), do: str |> String.codepoints() |> Enum.reverse() |> Enum.join()
      end
      """

      log =
        capture_log(fn ->
          result =
            Credence.fix(code,
              rules: [Credence.Pattern.NoCodepointStringReverse],
              assumptions: :strict
            )

          # still filtered: code unchanged
          assert result.code == code
        end)

      assert log =~ "NoCodepointStringReverse"
      assert log =~ "single_codepoint_graphemes"
    end
  end
end
