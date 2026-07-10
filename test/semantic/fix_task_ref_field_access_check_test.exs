defmodule Credence.Semantic.FixTaskRefFieldAccessCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixTaskRefFieldAccess

  # The real diagnostic captured from the pipeline (verbatim).
  @real_diag %{
    severity: :error,
    message:
      "you are trying to use/import/require the module RetryDedup.Application which is currently being defined.\n\nThis may happen if you accidentally override the module you want to use. For example:\n\n    defmodule MyApp do\n      defmodule Supervisor do\n        use Supervisor\n      end\n    end\n\nIn the example above, the new Supervisor conflicts with Elixir's Supervisor. This may be fixed by using the fully qualified name in the definition:\n\n    defmodule MyApp.Supervisor do\n      use Supervisor\n    end\n",
    position: 211
  }

  test "matches the diagnostic" do
    assert FixTaskRefFieldAccess.match?(@real_diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}}
    refute FixTaskRefFieldAccess.match?(diag)
  end

  test "ignores diagnostics with wrong severity" do
    diag = %{severity: :warning, message: @real_diag.message, position: {1, 1}}
    refute FixTaskRefFieldAccess.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert FixTaskRefFieldAccess.to_issue(@real_diag).rule == :fix_task_ref_field_access
  end

  test "issue preserves the diagnostic message" do
    assert FixTaskRefFieldAccess.to_issue(@real_diag).message == @real_diag.message
  end

  test "issue captures line from integer position" do
    assert FixTaskRefFieldAccess.to_issue(@real_diag).meta.line == 211
  end

  test "issue captures line from tuple position" do
    diag = %{@real_diag | position: {42, 10}}
    assert FixTaskRefFieldAccess.to_issue(diag).meta.line == 42
  end
end
