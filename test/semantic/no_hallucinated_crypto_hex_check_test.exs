defmodule Credence.Semantic.NoHallucinatedCryptoHexCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoHallucinatedCryptoHex

  @real_message ":crypto.hex/1 is undefined or private. Did you mean:\n\n    * hash/2\n    * hash/3\n"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {3, 5}}
    assert NoHallucinatedCryptoHex.match?(diag)
  end

  test "matches the diagnostic without hint" do
    diag = %{severity: :warning, message: ":crypto.hex/1 is undefined or private", position: {3, 5}}
    assert NoHallucinatedCryptoHex.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoHallucinatedCryptoHex.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module HallucinatedCryptoHex (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute NoHallucinatedCryptoHex.match?(diag)
  end

  test "ignores :crypto.hash warning" do
    diag = %{severity: :warning, message: ":crypto.hash/2 is deprecated", position: {1, 1}}
    refute NoHallucinatedCryptoHex.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {3, 5}}
    assert NoHallucinatedCryptoHex.to_issue(diag).rule == :no_hallucinated_crypto_hex
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {42, 10}}
    assert NoHallucinatedCryptoHex.to_issue(diag).meta.line == 42
  end
end
