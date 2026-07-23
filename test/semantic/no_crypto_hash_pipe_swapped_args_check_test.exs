defmodule Credence.Semantic.NoCryptoHashPipeSwappedArgsCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoCryptoHashPipeSwappedArgs

  @real_message "** (ArgumentError) errors were found at the given position:\n\n  * 2nd argument: not an iodata term\n\n    (crypto :erlang.crypto.hash/2)"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {7, 5}}
    assert NoCryptoHashPipeSwappedArgs.match?(diag)
  end

  test "matches with minimal message" do
    diag = %{severity: :error, message: "not an iodata term", position: {3, 1}}
    assert NoCryptoHashPipeSwappedArgs.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoCryptoHashPipeSwappedArgs.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {7, 5}}
    assert NoCryptoHashPipeSwappedArgs.to_issue(diag).rule == :no_crypto_hash_pipe_swapped_args
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {42, 10}}
    assert NoCryptoHashPipeSwappedArgs.to_issue(diag).meta.line == 42
  end
end
