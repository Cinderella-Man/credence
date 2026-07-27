defmodule Credence.Semantic.FixHallucinatedStreamDataFlatMapCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixHallucinatedStreamDataFlatMap

  test "matches the diagnostic" do
    diag = %{
      severity: :error,
      message: "function StreamData.flat_map/2 is undefined or private",
      position: {3, 3}
    }

    assert FixHallucinatedStreamDataFlatMap.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixHallucinatedStreamDataFlatMap.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{
      severity: :error,
      message: "function StreamData.flat_map/2 is undefined or private",
      position: {3, 3}
    }

    assert FixHallucinatedStreamDataFlatMap.to_issue(diag).rule ==
             :fix_hallucinated_stream_data_flat_map
  end
end
