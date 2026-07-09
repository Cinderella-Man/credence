defmodule Credence.Semantic.NoPrivateNamedEtsReadableExternallyCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoPrivateNamedEtsReadableExternally

  # The real diagnostic Elixir emits for the private-ETS-with-external-read pattern.
  # Copied verbatim from the captured diagnostic — the distinctive substring is
  # "incompatible types in binary construction" which appears in the type warning
  # for String.to_atom(to_string(name)) used as a binary in the name_to_table helper.
  @real_message "incompatible types in binary construction:\n\n    <<String.to_atom(to_string(name))::binary, ...>>\n\ngot type:\n\n    dynamic(atom())\n\nbut expected type:\n\n    binary()\n\nwhere \"name\" was given the type:\n\n    # type: dynamic()\n    # from: credence_check.ex:154:22\n    name\n"

  describe "match?/1" do
    test "matches the real diagnostic" do
      diag = %{severity: :warning, message: @real_message, position: {158, 1}}
      assert NoPrivateNamedEtsReadableExternally.match?(diag)
    end

    test "ignores unrelated diagnostics" do
      diag = %{severity: :warning, message: "unrelated warning", position: {1, 1}}
      refute NoPrivateNamedEtsReadableExternally.match?(diag)
    end

    test "ignores errors with similar phrasing" do
      diag = %{severity: :error, message: @real_message, position: {1, 1}}
      refute NoPrivateNamedEtsReadableExternally.match?(diag)
    end

    test "ignores generic compile errors" do
      diag = %{
        severity: :warning,
        message: "credence_check.ex: cannot compile module WeightedLRUCache (errors have been logged)",
        position: 0
      }

      refute NoPrivateNamedEtsReadableExternally.match?(diag)
    end
  end

  describe "to_issue/1" do
    test "builds issue with correct rule and line" do
      diag = %{severity: :warning, message: @real_message, position: {158, 1}}
      issue = NoPrivateNamedEtsReadableExternally.to_issue(diag)
      assert issue.rule == :no_private_named_ets_readable_externally
      assert issue.meta.line == 158
    end

    test "handles bare integer position" do
      diag = %{severity: :warning, message: @real_message, position: 158}
      assert NoPrivateNamedEtsReadableExternally.to_issue(diag).meta.line == 158
    end
  end
end
