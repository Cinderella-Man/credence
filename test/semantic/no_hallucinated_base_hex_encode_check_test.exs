defmodule Credence.Semantic.NoHallucinatedBaseHexEncodeCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoHallucinatedBaseHexEncode

  @real_message "Base.hex_encode/1 is undefined or private. Did you mean:\n\n    * encode16/2\n"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {3, 40}}
    assert NoHallucinatedBaseHexEncode.match?(diag)
  end

  test "matches the diagnostic without hint" do
    diag = %{severity: :warning, message: "Base.hex_encode/1 is undefined or private", position: {3, 40}}
    assert NoHallucinatedBaseHexEncode.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoHallucinatedBaseHexEncode.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module CsvImporter (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute NoHallucinatedBaseHexEncode.match?(diag)
  end

  test "ignores Base.encode16 warning" do
    diag = %{severity: :warning, message: "Base.encode16/2 is deprecated", position: {1, 1}}
    refute NoHallucinatedBaseHexEncode.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {3, 40}}
    assert NoHallucinatedBaseHexEncode.to_issue(diag).rule == :no_hallucinated_base_hex_encode
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {42, 10}}
    assert NoHallucinatedBaseHexEncode.to_issue(diag).meta.line == 42
  end
end
