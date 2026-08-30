defmodule Credence.Semantic.FixCaseBranchAssignmentScopeFixTest do
  use ExUnit.Case, async: true

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixCaseBranchAssignmentScope

  @message "undefined variable \"label\""

  defp fix(source, message, position) do
    FixCaseBranchAssignmentScope.fix(source, %{
      severity: :error,
      message: message,
      position: position
    })
  end

  test "fixes case branch assignment hoisting" do
    input = ~S"""
    defmodule M do
      def classify(x) do
        case x do
          :ok -> label = "success"
          :error -> label = "failure"
          _ -> label = "unknown"
        end

        String.upcase(label)
      end
    end
    """

    expected = ~S"""
    defmodule M do
      def classify(x) do
        label =
          case x do
            :ok -> "success"
            :error -> "failure"
            _ -> "unknown"
          end

        String.upcase(label)
      end
    end
    """

    confirm_fix(fix(input, @message, {9, 19}), expected)
  end

  test "fixes case with two branches" do
    input = ~S"""
    defmodule M do
      def classify(x) do
        case x do
          :ok -> result = 1
          :error -> result = 2
        end

        result + 10
      end
    end
    """

    expected = ~S"""
    defmodule M do
      def classify(x) do
        result =
          case x do
            :ok -> 1
            :error -> 2
          end

        result + 10
      end
    end
    """

    confirm_fix(fix(input, "undefined variable \"result\"", {8, 5}), expected)
  end

  test "keeps earlier branch statements when a branch has a multi-statement body" do
    input = ~S"""
    defmodule M do
      def classify(x) do
        case x do
          :ok ->
            IO.puts("hit ok")
            label = "success"

          _ ->
            label = "unknown"
        end

        String.upcase(label)
      end
    end
    """

    expected = ~S"""
    defmodule M do
      def classify(x) do
        label =
          case x do
            :ok ->
              IO.puts("hit ok")
              "success"

            _ ->
              "unknown"
          end

        String.upcase(label)
      end
    end
    """

    confirm_fix(fix(input, @message, {12, 19}), expected)
  end

  test "end to end: the real compiler diagnostic reaches this rule through the phase" do
    input = ~S"""
    defmodule CaseBranchScopeE2E do
      def classify(x) do
        case x do
          :ok -> label = "success"
          :error -> label = "failure"
          _ -> label = "unknown"
        end

        String.upcase(label)
      end
    end
    """

    expected = ~S"""
    defmodule CaseBranchScopeE2E do
      def classify(x) do
        label =
          case x do
            :ok -> "success"
            :error -> "failure"
            _ -> "unknown"
          end

        String.upcase(label)
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule M do
      def classify(x) do
        case x do
          :ok -> label = "success"
          :error -> label = "failure"
          _ -> label = "unknown"
        end

        String.upcase(label)
      end
    end
    """

    assert valid_syntax?(fix(input, @message, {9, 19}))
  end

  test "returns source unchanged when no case branch assignment pattern" do
    input = ~S"""
    defmodule M do
      def classify(x) do
        label = to_string(x)
        String.upcase(label)
      end
    end
    """

    confirm_fix(fix(input, @message, {4, 20}), input)
  end

  test "returns source unchanged when variable is not used after case" do
    input = ~S"""
    defmodule M do
      def classify(x) do
        case x do
          :ok -> label = "success"
          :error -> label = "failure"
        end

        :ok
      end
    end
    """

    confirm_fix(fix(input, @message, {3, 5}), input)
  end

  test "does not treat a variable use inside a following function as a use in module scope" do
    input = ~S"""
    defmodule CaseBranchScopeFunctionBoundary do
      case :ok do
        :ok -> label = "success"
        _ -> label = "unknown"
      end

      def f, do: label
    end
    """

    fixed = fix(input, @message, {7, 14})

    confirm_fix(fixed, input)
    assert {:error, input_diagnostics} = Credence.RuleHelpers.compile_and_capture(input)
    assert {:error, fixed_diagnostics} = Credence.RuleHelpers.compile_and_capture(fixed)
    assert fixed_diagnostics == input_diagnostics
  end

  test "returns source unchanged when the diagnostic line is not on the use after the case" do
    # A valid function whose `label` is bound before the case (so its use
    # after the case compiles fine and refers to "init") must NOT be rewritten
    # when the actual error is an unrelated `label` in another function —
    # hoisting would silently change `a/1`'s return value.
    input = ~S"""
    defmodule M do
      def a(x) do
        label = "init"

        case x do
          :ok -> label = "s"
          _ -> label = "u"
        end

        String.upcase(label)
      end

      def b do
        IO.puts(label)
      end
    end
    """

    confirm_fix(fix(input, @message, {15, 13}), input)
  end

  test "returns source unchanged when a branch binds the variable through a pattern" do
    input = ~S"""
    defmodule M do
      def classify(x) do
        case x do
          :ok -> {:ok, label} = fetch(x)
          _ -> label = "unknown"
        end

        String.upcase(label)
      end
    end
    """

    confirm_fix(fix(input, @message, {8, 19}), input)
  end

  test "returns source unchanged when one branch does not assign the variable" do
    input = ~S"""
    defmodule M do
      def classify(x) do
        case x do
          :ok -> label = "success"
          _ -> IO.puts("no label")
        end

        String.upcase(label)
      end
    end
    """

    confirm_fix(fix(input, @message, {8, 19}), input)
  end

  test "returns source unchanged when the case subject itself uses the variable" do
    input = ~S"""
    defmodule M do
      def classify do
        case label do
          :ok -> label = "success"
          _ -> label = "unknown"
        end

        String.upcase(label)
      end
    end
    """

    confirm_fix(fix(input, @message, {8, 19}), input)
  end
end
