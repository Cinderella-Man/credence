defmodule Credence.Semantic.NoStructUpdateOnUntypedVariableFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoStructUpdateOnUntypedVariable

  @message "undefined variable \"context\""

  defp fix(source, message, line \\ 1) do
    NoStructUpdateOnUntypedVariable.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "adds struct pattern to function parameter" do
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

      def execute(
            %__MODULE__{} = context,
            action_fn
          )
          when is_function(action_fn, 1) do
        %__MODULE__{
          context
          | steps: context.steps ++ [%{type: :compensable, action: action_fn}]
        }
      end
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixed output is well-formed (parses)" do
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

    assert valid_syntax?(fix(input, @message))
  end

  test "returns source unchanged when variable not in function parameters" do
    input = """
    defmodule Example do
      def test do
        x + 1
      end
    end
    """

    result = fix(input, "undefined variable \"x\"")
    confirm_fix(result, input)
  end

  test "returns source unchanged when variable already typed" do
    input = """
    defmodule Saga do
      defstruct steps: []

      def execute(%__MODULE__{} = context, action_fn)
          when is_function(action_fn, 1) do
        %__MODULE__{
          context
          | steps: context.steps ++ [%{type: :compensable, action: action_fn}]
        }
      end
    end
    """

    result = fix(input, @message)
    confirm_fix(result, input)
  end

  test "handles function without guard" do
    input = """
    defmodule Saga do
      defstruct steps: []

      def execute(context, action_fn) do
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

      def execute(
            %__MODULE__{} = context,
            action_fn
          ) do
        %__MODULE__{
          context
          | steps: context.steps ++ [%{type: :compensable, action: action_fn}]
        }
      end
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "handles defp" do
    input = """
    defmodule Saga do
      defstruct steps: []

      def run(context, action_fn) do
        do_execute(context, action_fn)
      end

      defp do_execute(context, action_fn) do
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

      def run(context, action_fn) do
        do_execute(context, action_fn)
      end

      defp do_execute(
             %__MODULE__{} = context,
             action_fn
           ) do
        %__MODULE__{
          context
          | steps: context.steps ++ [%{type: :compensable, action: action_fn}]
        }
      end
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "matches the BEFORE/after from the spec" do
    input = """
    defmodule Saga do
      defstruct steps: []

      def step(saga, name, action_fn, compensate_fn)
          when is_function(action_fn, 1) and is_function(compensate_fn, 1) do
        %__MODULE__{
          saga
          | steps: saga.steps ++ [%{name: name, type: :compensable, action: action_fn, compensate: compensate_fn}]
        }
      end
    end
    """

    expected = """
    defmodule Saga do
      defstruct steps: []

      def step(%__MODULE__{} = saga, name, action_fn, compensate_fn)
          when is_function(action_fn, 1) and is_function(compensate_fn, 1) do
        %__MODULE__{
          saga
          | steps:
              saga.steps ++
                [%{name: name, type: :compensable, action: action_fn, compensate: compensate_fn}]
        }
      end
    end
    """

    confirm_fix(fix(input, "undefined variable \"saga\""), expected)
  end
end
