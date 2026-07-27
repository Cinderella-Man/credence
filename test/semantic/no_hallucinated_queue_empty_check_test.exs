defmodule Credence.Semantic.NoHallucinatedQueueEmptyCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoHallucinatedQueueEmpty

  @real_message ":queue.empty/0 is undefined or private. Did you mean:\n\n    * is_empty/1\n"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {3, 12}}
    assert NoHallucinatedQueueEmpty.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoHallucinatedQueueEmpty.match?(diag)
  end

  test "ignores undefined function for other modules" do
    diag = %{
      severity: :warning,
      message: ":other.empty/0 is undefined or private",
      position: {1, 1}
    }

    refute NoHallucinatedQueueEmpty.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {3, 12}}
    assert NoHallucinatedQueueEmpty.to_issue(diag).rule == :no_hallucinated_queue_empty
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {42, 10}}
    assert NoHallucinatedQueueEmpty.to_issue(diag).meta.line == 42
  end
end
