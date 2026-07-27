defmodule Credence.Semantic.NoHallucinatedCryptoCompareCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoHallucinatedCryptoCompare

  @real_message ":crypto.compare/2 is undefined or private. Did you mean:\n\n    * hash_equals/2\n"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {3, 12}}
    assert NoHallucinatedCryptoCompare.match?(diag)
  end

  test "matches the diagnostic without hint" do
    diag = %{severity: :warning, message: ":crypto.compare/2 is undefined or private", position: {3, 12}}
    assert NoHallucinatedCryptoCompare.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoHallucinatedCryptoCompare.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module SecureToken (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute NoHallucinatedCryptoCompare.match?(diag)
  end

  test "ignores :crypto.hash_equals warning" do
    diag = %{severity: :warning, message: ":crypto.hash_equals/2 is deprecated", position: {1, 1}}
    refute NoHallucinatedCryptoCompare.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {3, 12}}
    assert NoHallucinatedCryptoCompare.to_issue(diag).rule == :no_hallucinated_crypto_compare
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {42, 10}}
    assert NoHallucinatedCryptoCompare.to_issue(diag).meta.line == 42
  end
end
