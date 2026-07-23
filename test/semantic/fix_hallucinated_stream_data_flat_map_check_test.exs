defmodule Credence.Semantic.FixHallucinatedStreamDataFlatMapCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixHallucinatedStreamDataFlatMap

  # Real diagnostic shape from `Code.with_diagnostics/1` compiling the
  # flagship input in the fix test — the column points at `flat_map`.
  @message "StreamData.flat_map/2 is undefined or private"
  @diag %{severity: :warning, message: @message, position: {3, 16}}

  test "matches the StreamData.flat_map/2 diagnostic" do
    assert FixHallucinatedStreamDataFlatMap.match?(@diag)
  end

  test "the semantic phase dispatches this rule for the diagnostic" do
    winner =
      Credence.Semantic.Rule
      |> Credence.RuleHelpers.discover_rules()
      |> Enum.find(& &1.match?(@diag))

    assert winner == FixHallucinatedStreamDataFlatMap
  end

  test "premise: StreamData.bind/2 is real and StreamData.flat_map/2 is not" do
    # Calling `constant/1` loads the module, so `function_exported?/3` is
    # accurate for the two assertions that pin this rule's premise.
    assert %StreamData{} = StreamData.constant(:probe)
    assert function_exported?(StreamData, :bind, 2)
    refute function_exported?(StreamData, :flat_map, 2)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixHallucinatedStreamDataFlatMap.match?(diag)
  end

  test "ignores other arities (only /2 has a known-safe rename)" do
    diag = %{
      severity: :warning,
      message: "StreamData.flat_map/3 is undefined or private",
      position: {2, 16}
    }

    refute FixHallucinatedStreamDataFlatMap.match?(diag)
  end

  test "ignores a user module whose path merely ends in StreamData" do
    diag = %{
      severity: :warning,
      message: "MyApp.StreamData.flat_map/2 is undefined or private",
      position: {2, 22}
    }

    refute FixHallucinatedStreamDataFlatMap.match?(diag)
  end

  test "ignores the unavailable-module wording for a missing module" do
    diag = %{
      severity: :warning,
      message:
        "StreamData.flat_map/2 is undefined (module StreamData is not available or is yet to be defined)",
      position: {2, 16}
    }

    refute FixHallucinatedStreamDataFlatMap.match?(diag)
  end

  test "ignores error-severity diagnostics" do
    diag = %{severity: :error, message: @message, position: {3, 16}}
    refute FixHallucinatedStreamDataFlatMap.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module Foo (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute FixHallucinatedStreamDataFlatMap.match?(diag)
  end

  test "should_report? is true when the fix would rewrite the source" do
    source = """
    defmodule CredenceStreamDataFlatMapReports do
      def sized_lists do
        StreamData.flat_map(StreamData.integer(1..10), fn len ->
          StreamData.list_of(StreamData.constant(len), length: len)
        end)
      end
    end
    """

    assert FixHallucinatedStreamDataFlatMap.should_report?(@diag, source)
  end

  test "should_report? is false for the deliberately unfixed Elixir.-prefixed spelling" do
    source = """
    defmodule CredenceStreamDataFlatMapNoReport do
      def gen(g, f), do: Elixir.StreamData.flat_map(g, f)
    end
    """

    diag = %{severity: :warning, message: @message, position: {2, 40}}
    refute FixHallucinatedStreamDataFlatMap.should_report?(diag, source)
  end

  test "attributes the issue to this rule" do
    assert FixHallucinatedStreamDataFlatMap.to_issue(@diag).rule ==
             :fix_hallucinated_stream_data_flat_map
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @message, position: {42, 10}}
    assert FixHallucinatedStreamDataFlatMap.to_issue(diag).meta.line == 42
  end
end
