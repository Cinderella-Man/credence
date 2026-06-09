defmodule Credence.Semantic.NoDocSpecOutsideModuleCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoDocSpecOutsideModule

  test "matches the diagnostic for @doc" do
    diag = %{
      severity: :warning,
      message: "module attribute @doc was set outside module",
      position: {1, 1}
    }

    assert NoDocSpecOutsideModule.match?(diag)
  end

  test "matches the diagnostic for @spec" do
    diag = %{
      severity: :error,
      message: "module attribute @spec was set outside module",
      position: {13, 1}
    }

    assert NoDocSpecOutsideModule.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoDocSpecOutsideModule.match?(diag)
  end

  test "ignores @moduledoc (no @doc or @spec substring)" do
    diag = %{
      severity: :warning,
      message: "module attribute @moduledoc was set outside module",
      position: {1, 1}
    }

    refute NoDocSpecOutsideModule.match?(diag)
  end

  test "ignores @doc message that lacks 'outside module'" do
    diag = %{severity: :warning, message: "@doc must be a string", position: {5, 3}}
    refute NoDocSpecOutsideModule.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{
      severity: :warning,
      message: "module attribute @doc was set outside module",
      position: {1, 1}
    }

    assert NoDocSpecOutsideModule.to_issue(diag).rule == :no_doc_spec_outside_module
  end

  test "preserves the diagnostic message in the issue" do
    diag = %{
      severity: :warning,
      message: "module attribute @spec was set outside module",
      position: {13, 5}
    }

    assert NoDocSpecOutsideModule.to_issue(diag).message ==
             "module attribute @spec was set outside module"
  end

  test "preserves the line number in the issue meta" do
    diag = %{
      severity: :warning,
      message: "module attribute @doc was set outside module",
      position: {7, 3}
    }

    assert NoDocSpecOutsideModule.to_issue(diag).meta.line == 7
  end
end