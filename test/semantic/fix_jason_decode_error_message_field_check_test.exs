defmodule Credence.Semantic.FixJasonDecodeErrorMessageFieldCheckTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2]

  alias Credence.Semantic.FixJasonDecodeErrorMessageField

  @real_message "unknown key :message for struct Jason.DecodeError"

  test "matches the diagnostic" do
    diag = %{
      severity: :error,
      message: @real_message,
      position: {148, 16},
      file: "credence_check.ex"
    }

    assert FixJasonDecodeErrorMessageField.match?(diag)
  end

  test "dispatches the compiler diagnostic through the semantic pipeline" do
    input = ~S"""
    defmodule JasonDecodeErrorMessageFieldSemanticPipelineFixture do
      def message(error) do
        case error do
          %Jason.DecodeError{message: msg} -> msg
        end
      end
    end
    """

    expected = ~S"""
    defmodule JasonDecodeErrorMessageFieldSemanticPipelineFixture do
      def message(error) do
        case error do
          %Jason.DecodeError{} = error -> Exception.message(error)
        end
      end
    end
    """

    {:ok, diagnostics} = Credence.RuleHelpers.compile_and_capture(input)

    assert Enum.any?(
             diagnostics,
             &(&1.severity == :error and &1.message == @real_message and
                 FixJasonDecodeErrorMessageField.match?(&1))
           )

    fixed = Credence.Semantic.fix(input)

    confirm_fix(fixed, expected)
    assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(fixed)
    assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(expected)
  end

  test "ignores unrelated diagnostics" do
    diag = %{
      severity: :error,
      message: "unrelated error",
      position: {1, 1},
      file: "credence_check.ex"
    }

    refute FixJasonDecodeErrorMessageField.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module Factory (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute FixJasonDecodeErrorMessageField.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{
      severity: :error,
      message: @real_message,
      position: {148, 16},
      file: "credence_check.ex"
    }

    assert FixJasonDecodeErrorMessageField.to_issue(diag).rule ==
             :fix_jason_decode_error_message_field
  end

  test "sets the line in issue meta" do
    diag = %{
      severity: :error,
      message: @real_message,
      position: {42, 16},
      file: "credence_check.ex"
    }

    assert FixJasonDecodeErrorMessageField.to_issue(diag).meta.line == 42
  end
end
