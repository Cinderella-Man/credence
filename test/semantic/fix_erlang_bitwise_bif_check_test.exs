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
    message:
      "undefined function bsl/2 (expected Test to define such a function or for it to be imported, but none are available)",
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

  test "ignores bsl called with the wrong arity" do
    # bsl/3 has no same-answer rewrite: Bitwise.bsl/3 does not exist, so
    # prefixing would trade the compile error for a runtime crash.
    diag = %{severity: :error, message: "undefined function bsl/3", position: {1, 1}}
    refute FixErlangBitwiseBif.match?(diag)
  end

  test "ignores bnot called with the wrong arity" do
    diag = %{severity: :error, message: "undefined function bnot/2", position: {1, 1}}
    refute FixErlangBitwiseBif.match?(diag)
  end

  test "ignores band called with the wrong arity" do
    diag = %{severity: :error, message: "undefined function band/1", position: {1, 1}}
    refute FixErlangBitwiseBif.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert FixErlangBitwiseBif.to_issue(@bsl_diag).rule == :fix_erlang_bitwise_bif
  end

  test "issue message names the exact replacement for bsl/2" do
    assert FixErlangBitwiseBif.to_issue(@bsl_diag).message ==
             "undefined function bsl/2; use Bitwise.bsl instead"
  end

  test "issue message names the exact replacement for |||/2" do
    assert FixErlangBitwiseBif.to_issue(@real_diag).message ==
             "undefined function |||/2; use Bitwise.bor instead"
  end

  test "issue carries the diagnostic line" do
    assert FixErlangBitwiseBif.to_issue(@real_diag).meta.line == 65
  end

  test "end-to-end: a real bsl/2 diagnostic dispatches to this rule" do
    source = """
    defmodule FixErlangBitwiseBifCheckE2E do
      def left_shift(value, n) do
        bsl(value, n)
      end
    end
    """

    assert [
             %Credence.Issue{
               rule: :fix_erlang_bitwise_bif,
               message: "undefined function bsl/2; use Bitwise.bsl instead",
               meta: %{line: 3}
             }
           ] = Credence.Semantic.analyze(source)
  end
end
