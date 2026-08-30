defmodule Credence.Semantic.FixHallucinatedMapsetAnyCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixHallucinatedMapsetAny

  # Real diagnostic shape from `Code.with_diagnostics/1` compiling the
  # flagship input in the fix test — the column points at `any?`.
  @message "MapSet.any?/2 is undefined or private"
  @diag %{severity: :warning, message: @message, position: {3, 12}}

  test "matches the MapSet.any?/2 diagnostic" do
    assert FixHallucinatedMapsetAny.match?(@diag)
  end

  test "the semantic phase dispatches this rule for the diagnostic" do
    winner =
      Credence.Semantic.Rule
      |> Credence.RuleHelpers.discover_rules()
      |> Enum.find(& &1.match?(@diag))

    assert winner == FixHallucinatedMapsetAny
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixHallucinatedMapsetAny.match?(diag)
  end

  test "ignores other arities (MapSet.any?/1 has ambiguous intent)" do
    diag = %{
      severity: :warning,
      message: "MapSet.any?/1 is undefined or private",
      position: {2, 12}
    }

    refute FixHallucinatedMapsetAny.match?(diag)
  end

  test "ignores a user module whose path merely ends in MapSet" do
    diag = %{
      severity: :warning,
      message: "MyApp.MapSet.any?/2 is undefined or private",
      position: {2, 21}
    }

    refute FixHallucinatedMapsetAny.match?(diag)
  end

  test "ignores the unavailable-module wording for a missing module" do
    diag = %{
      severity: :warning,
      message:
        "MyMapSet.any?/2 is undefined (module MyMapSet is not available or is yet to be defined)",
      position: {2, 21}
    }

    refute FixHallucinatedMapsetAny.match?(diag)
  end

  test "ignores error-severity diagnostics" do
    diag = %{severity: :error, message: @message, position: {3, 12}}
    refute FixHallucinatedMapsetAny.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module Foo (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute FixHallucinatedMapsetAny.match?(diag)
  end

  test "should_report? is true when the fix would rewrite the source" do
    source = """
    defmodule CredenceMapsetAnyReports do
      def has_active?(mapset, tombstones) do
        MapSet.any?(mapset, fn tag -> not MapSet.member?(tombstones, tag) end)
      end
    end
    """

    assert FixHallucinatedMapsetAny.should_report?(@diag, source)
  end

  test "should_report? is false for the deliberately unfixed Elixir.-prefixed spelling" do
    source = """
    defmodule CredenceMapsetAnyNoReport do
      def a(s, p), do: Elixir.MapSet.any?(s, p)
    end
    """

    diag = %{severity: :warning, message: @message, position: {2, 34}}
    refute FixHallucinatedMapsetAny.should_report?(diag, source)
  end

  test "attributes the issue to this rule" do
    assert FixHallucinatedMapsetAny.to_issue(@diag).rule == :fix_hallucinated_mapset_any
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @message, position: {42, 10}}
    assert FixHallucinatedMapsetAny.to_issue(diag).meta.line == 42
  end
end
