defmodule Credence.Semantic.NoStructUpdateOnUntypedVariableCheckTest do
  use ExUnit.Case, async: true

  alias Credence.Semantic.NoStructUpdateOnUntypedVariable, as: Rule

  # Verbatim `Code.with_diagnostics/1` output on Elixir 1.20.2 for the module in
  # `@source` below (severity `:warning`, position `{5, 5}`).
  @real_message """
  a struct for Saga is expected on struct update:

      %Saga{context | steps: context.steps ++ [action_fn]}

  but got type:

      dynamic()

  where "context" was given the type:

      # type: dynamic()
      # from: credence_check.ex:4:15
      context

  when defining the variable "context", you must also pattern match on "%Saga{}"
  """

  @source """
  defmodule Saga do
    defstruct steps: []

    def execute(context, action_fn) when is_function(action_fn, 1) do
      %__MODULE__{context | steps: context.steps ++ [action_fn]}
    end
  end
  """

  defp diagnostic(message \\ @real_message) do
    %{severity: :warning, message: message, position: {5, 5}, file: "credence_check.ex"}
  end

  describe "the diagnostic this rule is keyed on is real" do
    test "the compiler emits @real_message for @source" do
      assert [%{severity: :warning, message: message, position: {5, 5}}] =
               struct_update_diagnostics(@source)

      assert message == @real_message
    end

    test "the fix resolves the diagnostic" do
      assert struct_update_diagnostics(Rule.fix(@source, diagnostic())) == []
    end
  end

  # Only the diagnostics this rule claims, taken from the same production entry
  # point the Semantic phase uses. Compiling the same module name twice also
  # emits a "redefining module" warning — an artifact of compiling fixtures
  # in-process, not of the fixture.
  defp struct_update_diagnostics(source) do
    {:ok, diagnostics} = Credence.RuleHelpers.compile_and_capture(source)
    Enum.filter(diagnostics, &Rule.match?/1)
  end

  describe "match?/1" do
    test "matches the struct-update diagnostic" do
      assert Rule.match?(diagnostic())
    end

    test "ignores unrelated diagnostics" do
      refute Rule.match?(diagnostic("undefined function foo/1"))
    end

    test "ignores a struct-update message with no variable named in it" do
      refute Rule.match?(diagnostic("a struct for Saga is expected on struct update:\n"))
    end

    test "ignores non-diagnostic input" do
      refute Rule.match?(%{severity: :warning})
      refute Rule.match?(nil)
    end
  end

  describe "to_issue/1" do
    test "attributes the issue to this rule" do
      assert Rule.to_issue(diagnostic()).rule == :no_struct_update_on_untyped_variable
    end

    test "sets the line in issue meta" do
      assert Rule.to_issue(%{diagnostic() | position: {10, 5}}).meta.line == 10
    end

    test "accepts a bare integer position" do
      assert Rule.to_issue(%{diagnostic() | position: 7}).meta.line == 7
    end
  end

  # `should_report?/2` is the phase hook that keeps `analyze` honest: an issue is
  # reported only for the shapes `fix/2` actually rewrites.
  describe "should_report?/2 — reported" do
    test "bare parameter, sole clause, body is the struct update" do
      assert Rule.should_report?(diagnostic(), @source)
    end

    test "the struct spelled as a plain alias" do
      source = """
      defmodule Saga do
        defstruct steps: []

        def execute(context, action_fn) do
          %Saga{context | steps: context.steps ++ [action_fn]}
        end
      end
      """

      assert Rule.should_report?(diagnostic(), source)
    end
  end

  # Every case below is one the fix deliberately declines — see the moduledoc's
  # "What is deliberately left alone". They are pinned here so the safety choice
  # cannot be loosened without a failing test.
  describe "should_report?/2 — not reported" do
    test "the struct update sits inside a branch (a non-struct returns a value today)" do
      source = """
      defmodule Saga do
        defstruct steps: []

        def execute(context, action_fn) do
          if valid?(context) do
            %__MODULE__{context | steps: [action_fn]}
          else
            :error
          end
        end

        def valid?(_), do: true
      end
      """

      refute Rule.should_report?(diagnostic(), source)
    end

    test "the body has statements before the struct update (their side effects would stop running)" do
      source = """
      defmodule Saga do
        defstruct steps: []

        def execute(context, action_fn) do
          IO.puts("stepping")
          %__MODULE__{context | steps: [action_fn]}
        end
      end
      """

      refute Rule.should_report?(diagnostic(), source)
    end

    test "another clause of the same name/arity could catch the argument instead" do
      source = """
      defmodule Saga do
        defstruct steps: []

        def execute(context, action_fn) when is_map(context) do
          %__MODULE__{context | steps: [action_fn]}
        end

        def execute(context, _action_fn), do: context
      end
      """

      refute Rule.should_report?(diagnostic(), source)
    end

    test "a bodyless head declares defaults for the same name/arity" do
      source = """
      defmodule Saga do
        defstruct steps: []

        def execute(context, action_fn \\\\ nil)

        def execute(context, action_fn) do
          %__MODULE__{context | steps: [action_fn]}
        end
      end
      """

      refute Rule.should_report?(diagnostic(), source)
    end

    test "the variable is not a parameter of the clause" do
      source = """
      defmodule Saga do
        defstruct steps: []

        def execute(action_fn) do
          %__MODULE__{context | steps: [action_fn]}
        end
      end
      """

      refute Rule.should_report?(diagnostic(), source)
    end

    test "the variable is already typed in the head" do
      source = """
      defmodule Saga do
        defstruct steps: []

        def execute(%__MODULE__{} = context, action_fn) do
          %__MODULE__{context | steps: [action_fn]}
        end
      end
      """

      refute Rule.should_report?(diagnostic(), source)
    end

    test "the parameter is destructured rather than bare" do
      source = """
      defmodule Saga do
        defstruct steps: []

        def execute({context, _tag}, action_fn) do
          %__MODULE__{context | steps: [action_fn]}
        end
      end
      """

      refute Rule.should_report?(diagnostic(), source)
    end

    test "the clause has a rescue block" do
      source = """
      defmodule Saga do
        defstruct steps: []

        def execute(context, action_fn) do
          %__MODULE__{context | steps: [action_fn]}
        rescue
          _ -> :error
        end
      end
      """

      refute Rule.should_report?(diagnostic(), source)
    end

    test "the struct update is not the one named by the diagnostic's variable" do
      source = """
      defmodule Saga do
        defstruct steps: []

        def execute(other, action_fn) do
          %__MODULE__{other | steps: [action_fn]}
        end
      end
      """

      refute Rule.should_report?(diagnostic(), source)
    end

    test "the source does not parse" do
      refute Rule.should_report?(diagnostic(), "defmodule Saga do\n  def execute(context")
    end
  end
end
