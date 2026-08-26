defmodule Credence.Semantic.NoStructUpdateOnUntypedVariableFixTest do
  use ExUnit.Case, async: true

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoStructUpdateOnUntypedVariable, as: Rule

  defp message(var, struct \\ "Saga") do
    ~s(a struct for #{struct} is expected on struct update:\n\n) <>
      ~s(when defining the variable "#{var}", you must also pattern match on "%#{struct}{}"\n)
  end

  defp fix(source, var \\ "context") do
    Rule.fix(source, %{severity: :warning, message: message(var), position: {5, 5}})
  end

  describe "rewrites" do
    test "preserves plain-map returns and the original exception classes" do
      source = """
      defmodule SagaRuntimeEquivalenceNSUOUV do
        defstruct steps: []

        def execute(context, action_fn) do
          %__MODULE__{context | steps: [action_fn]}
        end

        def outcome(value) do
          try do
            {:ok, execute(value, :action)}
          rescue
            error -> {:raise, error.__struct__}
          end
        end
      end

      outcomes = Enum.map([%{steps: []}, %{}, nil, 7], &SagaRuntimeEquivalenceNSUOUV.outcome/1)

      unless outcomes == [
               {:ok, %{steps: [:action]}},
               {:raise, KeyError},
               {:raise, BadMapError},
               {:raise, BadMapError}
             ], do: raise("unexpected outcomes: \#{inspect(outcomes)}")
      """

      assert {:ok, [diagnostic]} = Credence.RuleHelpers.compile_and_capture(source)
      fixed = Rule.fix(source, diagnostic)
      refute fixed == source
      assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(fixed)
    end

    test "removes the struct qualifier, leaving every other byte alone" do
      input = """
      defmodule Saga do
        defstruct steps: []

        def execute(context, action_fn)
            when is_function(action_fn, 1) do
          %__MODULE__{
            context
            | steps: context.steps ++ [%{type: :compensable, action: action_fn}]
          }
        end
      end
      """

      expected = """
      defmodule Saga do
        defstruct steps: []

        def execute(context, action_fn)
            when is_function(action_fn, 1) do
          %{
            context
            | steps: context.steps ++ [%{type: :compensable, action: action_fn}]
          }
        end
      end
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "handles a clause with no guard" do
      input = """
      defmodule Saga do
        defstruct steps: []

        def execute(context, action_fn) do
          %__MODULE__{context | steps: context.steps ++ [action_fn]}
        end
      end
      """

      expected = """
      defmodule Saga do
        defstruct steps: []

        def execute(context, action_fn) do
          %{context | steps: context.steps ++ [action_fn]}
        end
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "handles defp" do
      input = """
      defmodule Saga do
        defstruct steps: []

        def run(context, action_fn) do
          do_execute(context, action_fn)
        end

        defp do_execute(context, action_fn) do
          %__MODULE__{context | steps: context.steps ++ [action_fn]}
        end
      end
      """

      expected = """
      defmodule Saga do
        defstruct steps: []

        def run(context, action_fn) do
          do_execute(context, action_fn)
        end

        defp do_execute(context, action_fn) do
          %{context | steps: context.steps ++ [action_fn]}
        end
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "handles a parameter that is not the first one" do
      input = """
      defmodule Saga do
        defstruct steps: []

        def step(name, saga, action_fn) do
          %__MODULE__{saga | steps: [{name, action_fn}]}
        end
      end
      """

      expected = """
      defmodule Saga do
        defstruct steps: []

        def step(name, saga, action_fn) do
          %{saga | steps: [{name, action_fn}]}
        end
      end
      """

      confirm_fix(fix(input, "saga"), expected)
    end

    test "writes the same struct name the body uses when it is a plain alias" do
      input = """
      defmodule Saga do
        defstruct steps: []

        def execute(context, action_fn) do
          %Saga{context | steps: [action_fn]}
        end
      end
      """

      expected = """
      defmodule Saga do
        defstruct steps: []

        def execute(context, action_fn) do
          %{context | steps: [action_fn]}
        end
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "writes a dotted alias unchanged" do
      input = """
      defmodule My.Saga do
        defstruct steps: []

        def execute(context, action_fn) do
          %My.Saga{context | steps: [action_fn]}
        end
      end
      """

      expected = """
      defmodule My.Saga do
        defstruct steps: []

        def execute(context, action_fn) do
          %{context | steps: [action_fn]}
        end
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "fixes every qualifying clause the variable names" do
      input = """
      defmodule Saga do
        defstruct steps: []

        def one(context, action_fn) do
          %__MODULE__{context | steps: [action_fn]}
        end

        def two(context) do
          %__MODULE__{context | steps: []}
        end
      end
      """

      expected = """
      defmodule Saga do
        defstruct steps: []

        def one(context, action_fn) do
          %{context | steps: [action_fn]}
        end

        def two(context) do
          %{context | steps: []}
        end
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "preserves comments and unrelated layout" do
      input = """
      defmodule Saga do
        defstruct steps: []

        # keep me
        def execute(context, action_fn) do
          %__MODULE__{context | steps: context.steps ++ [   action_fn]}
        end

        def untouched, do:    :ok
      end
      """

      expected = """
      defmodule Saga do
        defstruct steps: []

        # keep me
        def execute(context, action_fn) do
          %{context | steps: context.steps ++ [   action_fn]}
        end

        def untouched, do:    :ok
      end
      """

      confirm_fix(fix(input), expected)
    end
  end

  # Each no-op below mirrors a "not reported" case in the check test — check and
  # fix agree, so nothing is ever flagged that the fix declines to touch.
  describe "no-ops" do
    test "the struct update sits inside a branch" do
      input = """
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

      confirm_fix(fix(input), input)
    end

    test "the body has statements before the struct update" do
      input = """
      defmodule Saga do
        defstruct steps: []

        def execute(context, action_fn) do
          IO.puts("stepping")
          %__MODULE__{context | steps: [action_fn]}
        end
      end
      """

      confirm_fix(fix(input), input)
    end

    test "another clause of the same name/arity exists" do
      input = """
      defmodule Saga do
        defstruct steps: []

        def execute(context, action_fn) when is_map(context) do
          %__MODULE__{context | steps: [action_fn]}
        end

        def execute(context, _action_fn), do: context
      end
      """

      confirm_fix(fix(input), input)
    end

    test "a bodyless head declares defaults for the same name/arity" do
      input = """
      defmodule Saga do
        defstruct steps: []

        def execute(context, action_fn \\\\ nil)

        def execute(context, action_fn) do
          %__MODULE__{context | steps: [action_fn]}
        end
      end
      """

      confirm_fix(fix(input), input)
    end

    test "the variable is already typed in the head" do
      input = """
      defmodule Saga do
        defstruct steps: []

        def execute(%__MODULE__{} = context, action_fn) do
          %__MODULE__{context | steps: [action_fn]}
        end
      end
      """

      confirm_fix(fix(input), input)
    end

    test "the parameter is destructured rather than bare" do
      input = """
      defmodule Saga do
        defstruct steps: []

        def execute({context, _tag}, action_fn) do
          %__MODULE__{context | steps: [action_fn]}
        end
      end
      """

      confirm_fix(fix(input), input)
    end

    test "the clause has a rescue block" do
      input = """
      defmodule Saga do
        defstruct steps: []

        def execute(context, action_fn) do
          %__MODULE__{context | steps: [action_fn]}
        rescue
          _ -> :error
        end
      end
      """

      confirm_fix(fix(input), input)
    end

    test "the variable is not a parameter of the clause" do
      input = """
      defmodule Saga do
        defstruct steps: []

        def execute(action_fn) do
          %__MODULE__{context | steps: [action_fn]}
        end
      end
      """

      confirm_fix(fix(input), input)
    end

    test "the struct is not a literal module name" do
      input = """
      defmodule Saga do
        defstruct steps: []

        def execute(context, mod) do
          %mod{context | steps: []}
        end
      end
      """

      confirm_fix(fix(input), input)
    end

    test "the variable appears twice as a bare parameter" do
      input = """
      defmodule Saga do
        defstruct steps: []

        def execute(context, context) do
          %__MODULE__{context | steps: []}
        end
      end
      """

      confirm_fix(fix(input), input)
    end

    test "the source does not parse" do
      input = """
      defmodule Saga do
        def execute(context
      """

      confirm_fix(fix(input), input)
    end

    test "the diagnostic names no variable" do
      input = """
      defmodule Saga do
        defstruct steps: []

        def execute(context, action_fn) do
          %__MODULE__{context | steps: [action_fn]}
        end
      end
      """

      confirm_fix(
        Rule.fix(input, %{severity: :warning, message: "boom", position: {1, 1}}),
        input
      )

      confirm_fix(Rule.fix(input, %{severity: :warning, position: {1, 1}}), input)
    end
  end
end
