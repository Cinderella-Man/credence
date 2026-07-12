defmodule Credence.Semantic.NoHardcodedGenserverNameInApiCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoHardcodedGenserverNameInApi

  # The real diagnostic Elixir emits when a case clause uses :catch.
  # Copied verbatim from the captured diagnostic.
  @real_message "unexpected option :catch in \"case\""

  describe "match?/1" do
    test "matches the real diagnostic" do
      diag = %{severity: :error, message: @real_message, position: {77, 5}}
      assert NoHardcodedGenserverNameInApi.match?(diag)
    end

    test "ignores unrelated diagnostics" do
      diag = %{severity: :error, message: "unrelated error", position: {1, 1}}
      refute NoHardcodedGenserverNameInApi.match?(diag)
    end

    test "ignores warnings with similar phrasing" do
      diag = %{severity: :warning, message: @real_message, position: {1, 1}}
      refute NoHardcodedGenserverNameInApi.match?(diag)
    end

    test "ignores generic compile errors" do
      diag = %{
        severity: :error,
        message: "cannot compile module FeatureFlags (errors have been logged)",
        position: 0
      }

      refute NoHardcodedGenserverNameInApi.match?(diag)
    end
  end

  describe "to_issue/1" do
    test "builds issue with correct rule and line" do
      diag = %{severity: :error, message: @real_message, position: {77, 5}}
      issue = NoHardcodedGenserverNameInApi.to_issue(diag)
      assert issue.rule == :no_hardcoded_genserver_name_in_api
      assert issue.meta.line == 77
    end

    test "handles bare integer position" do
      diag = %{severity: :error, message: @real_message, position: 77}
      assert NoHardcodedGenserverNameInApi.to_issue(diag).meta.line == 77
    end
  end
end
