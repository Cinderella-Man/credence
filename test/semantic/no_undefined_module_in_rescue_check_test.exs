defmodule Credence.Semantic.NoUndefinedModuleInRescueCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoUndefinedModuleInRescue

  # Exactly what the compiler emits for `rescue e in [NotImplementedError, ...]`
  # (verified against `Code.with_diagnostics/1`).
  @real_message "struct NotImplementedError is undefined (module NotImplementedError is not available or is yet to be defined)"

  # Older Elixir versions append a hint sentence to the same warning.
  @legacy_message "struct NotImplementedError is undefined (module NotImplementedError is not available or is yet to be defined). Make sure the module name is correct and has been specified in full (or that an alias has been defined)"

  defp diag(message \\ @real_message, severity \\ :warning) do
    %{severity: severity, message: message, position: {104, 9}}
  end

  describe "match?/1" do
    test "matches the diagnostic the compiler really emits" do
      assert NoUndefinedModuleInRescue.match?(diag())
    end

    test "matches the older message that carries the hint sentence" do
      assert NoUndefinedModuleInRescue.match?(diag(@legacy_message))
    end

    test "matches with a different undefined module" do
      message =
        "struct BadStructError is undefined (module BadStructError is not available or is yet to be defined)"

      assert NoUndefinedModuleInRescue.match?(diag(message))
    end

    test "matches a fully-qualified undefined module" do
      message =
        "struct MyApp.BadStructError is undefined (module MyApp.BadStructError is not available or is yet to be defined)"

      assert NoUndefinedModuleInRescue.match?(diag(message))
    end

    test "ignores unrelated diagnostics" do
      refute NoUndefinedModuleInRescue.match?(diag("unrelated warning"))
    end

    test "ignores an undefined remote call rather than a struct" do
      message =
        "MyApp.Repo.insert!/1 is undefined (module MyApp.Repo is not available or is yet to be defined)"

      refute NoUndefinedModuleInRescue.match?(diag(message))
    end

    test "ignores the Exception behaviour warning owned by no_rescue_in_exception" do
      message =
        "struct Exception is undefined (there is such module but it does not define a struct)"

      refute NoUndefinedModuleInRescue.match?(diag(message))
    end

    # A struct *pattern* over an undefined module (`def f(%Undefined{} = e)`)
    # emits the same sentence at :error severity. There is no rescue list to
    # trim there, so the error variant stays unclaimed.
    test "ignores error severity" do
      refute NoUndefinedModuleInRescue.match?(diag(@real_message, :error))
    end

    test "ignores a diagnostic without a message" do
      refute NoUndefinedModuleInRescue.match?(%{severity: :warning, position: {1, 1}})
    end
  end

  describe "to_issue/1" do
    test "attributes the issue to this rule" do
      assert NoUndefinedModuleInRescue.to_issue(diag()).rule == :no_undefined_module_in_rescue
    end

    test "sets the line in issue meta" do
      assert NoUndefinedModuleInRescue.to_issue(diag()).meta.line == 104
    end

    test "accepts a bare integer position" do
      diagnostic = %{severity: :warning, message: @real_message, position: 7}
      assert NoUndefinedModuleInRescue.to_issue(diagnostic).meta.line == 7
    end

    test "passes through the diagnostic message" do
      assert NoUndefinedModuleInRescue.to_issue(diag()).message == @real_message
    end
  end

  describe "should_report?/2 — reports exactly what fix/2 repairs" do
    test "reports a multi-module rescue list" do
      source = """
      defmodule M do
        def run do
          try do
            :ok
          rescue
            e in [NotImplementedError, RuntimeError] -> e
          end
        end
      end
      """

      assert NoUndefinedModuleInRescue.should_report?(diag(), source)
    end

    # Emptying the list would mean rewriting to a catch-all `rescue e ->`,
    # which swallows every exception the clause used to let through.
    test "no issue for a rescue list that would be left empty" do
      source = """
      defmodule M do
        def run do
          try do
            :ok
          rescue
            e in [NotImplementedError] -> e
          end
        end
      end
      """

      refute NoUndefinedModuleInRescue.should_report?(diag(), source)
    end

    test "no issue for a non-list rescue head" do
      source = """
      defmodule M do
        def run do
          try do
            :ok
          rescue
            e in NotImplementedError -> e
          end
        end
      end
      """

      refute NoUndefinedModuleInRescue.should_report?(diag(), source)
    end

    # `in` outside a rescue head is `Enum.member?/2`, not a struct match.
    test "no issue for a membership test outside a rescue clause" do
      source = """
      defmodule M do
        def f(x), do: x in [NotImplementedError, RuntimeError]
      end
      """

      refute NoUndefinedModuleInRescue.should_report?(diag(), source)
    end

    test "no issue when the file aliases the flagged name" do
      source = """
      defmodule M do
        alias MyApp.NotImplementedError

        def run do
          try do
            :ok
          rescue
            e in [NotImplementedError, RuntimeError] -> e
          end
        end
      end
      """

      refute NoUndefinedModuleInRescue.should_report?(diag(), source)
    end

    test "no issue for a guarded rescue head" do
      source = """
      defmodule M do
        def run do
          try do
            :ok
          rescue
            e in [NotImplementedError, RuntimeError] when is_map(e) -> e
          end
        end
      end
      """

      refute NoUndefinedModuleInRescue.should_report?(diag(), source)
    end

    test "no issue when the flagged module is not in the source" do
      source = """
      defmodule M do
        def run do
          try do
            :ok
          rescue
            e in [ArgumentError, RuntimeError] -> e
          end
        end
      end
      """

      refute NoUndefinedModuleInRescue.should_report?(diag(), source)
    end

    test "no issue when the source does not parse" do
      refute NoUndefinedModuleInRescue.should_report?(diag(), "defmodule M do")
    end

    test "no issue when the message carries no module name" do
      message = "struct is undefined (module is not available or is yet to be defined)"

      source = """
      defmodule M do
        def run do
          try do
            :ok
          rescue
            e in [NotImplementedError, RuntimeError] -> e
          end
        end
      end
      """

      refute NoUndefinedModuleInRescue.should_report?(diag(message), source)
    end
  end
end
