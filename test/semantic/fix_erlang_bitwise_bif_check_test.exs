defmodule Credence.Semantic.FixErlangBitwiseBifCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixErlangBitwiseBif

  @real_diag %{
    severity: :error,
    message:
      "undefined function |||/2 (expected BloomFilter to define such a function or for it to be imported, but none are available)",
    position: {65, 12}
  }

  @bsl_diag %{
    severity: :error,
    message: "undefined function bsl/2",
    position: {3, 5}
  }

  test "matches the diagnostic for |||/2" do
    assert FixErlangBitwiseBif.match?(@real_diag)
  end

  test "matches the diagnostic for bsl/2" do
    assert FixErlangBitwiseBif.match?(@bsl_diag)
  end

  test "matches band/2" do
    diag = %{severity: :error, message: "undefined function band/2", position: {1, 1}}
    assert FixErlangBitwiseBif.match?(diag)
  end

  test "matches bnot/1" do
    diag = %{severity: :error, message: "undefined function bnot/1", position: {1, 1}}
    assert FixErlangBitwiseBif.match?(diag)
  end

  test "matches ^^^/2" do
    diag = %{severity: :error, message: "undefined function ^^^/2", position: {1, 1}}
    assert FixErlangBitwiseBif.match?(diag)
  end

  test "matches <<</2" do
    diag = %{severity: :error, message: "undefined function <<</2", position: {1, 1}}
    assert FixErlangBitwiseBif.match?(diag)
  end

  test "matches >>>/2" do
    diag = %{severity: :error, message: "undefined function >>>/2", position: {1, 1}}
    assert FixErlangBitwiseBif.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixErlangBitwiseBif.match?(diag)
  end

  test "ignores undefined function for non-bitwise BIF" do
    diag = %{severity: :error, message: "undefined function foo/2", position: {1, 1}}
    refute FixErlangBitwiseBif.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert FixErlangBitwiseBif.to_issue(@bsl_diag).rule == :fix_erlang_bitwise_bif
  end

  test "issue message mentions the fix" do
    assert FixErlangBitwiseBif.to_issue(@bsl_diag).message =~ "Bitwise.bsl"
  end

  test "issue message for |||/2 mentions Bitwise" do
    assert FixErlangBitwiseBif.to_issue(@real_diag).message =~ "Bitwise"
  end
end
