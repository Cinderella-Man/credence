defmodule Credence.Semantic.NoEtsInfoBareSizeCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoEtsInfoBareSize

  # The real diagnostic Elixir emits for `:ets.info(table, size)` — the bare
  # `size` is read as an undefined variable. Verified against the compiler.
  @real_message "undefined variable \"size\""

  describe "match?/1" do
    test "matches the undefined-variable error for size" do
      diag = %{severity: :error, message: @real_message, position: {16, 37}}
      assert NoEtsInfoBareSize.match?(diag)
    end

    test "ignores unrelated diagnostics" do
      diag = %{severity: :error, message: "undefined function foo/0", position: {2, 5}}
      refute NoEtsInfoBareSize.match?(diag)
    end

    test "ignores warnings with the same message" do
      diag = %{severity: :warning, message: @real_message, position: {16, 37}}
      refute NoEtsInfoBareSize.match?(diag)
    end

    test "ignores other undefined variables" do
      diag = %{severity: :error, message: "undefined variable \"other\"", position: {1, 1}}
      refute NoEtsInfoBareSize.match?(diag)
    end

    test "ignores generic compile errors" do
      diag = %{
        severity: :error,
        message: "credence_check.ex: cannot compile module LRUCache (errors have been logged)",
        position: 0
      }

      refute NoEtsInfoBareSize.match?(diag)
    end
  end

  describe "to_issue/1" do
    test "builds issue with correct rule and line" do
      diag = %{severity: :error, message: @real_message, position: {16, 37}}
      issue = NoEtsInfoBareSize.to_issue(diag)
      assert issue.rule == :no_ets_info_bare_size
      assert issue.meta.line == 16
    end

    test "handles bare integer position" do
      diag = %{severity: :error, message: @real_message, position: 16}
      assert NoEtsInfoBareSize.to_issue(diag).meta.line == 16
    end
  end
end
