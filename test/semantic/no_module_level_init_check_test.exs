defmodule Credence.Semantic.NoModuleLevelInitCheckTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2]

  alias Credence.RuleHelpers
  alias Credence.Semantic.NoModuleLevelInit

  @real_message "undefined function init/0 (there is no such import)"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {24, 3}}
    assert NoModuleLevelInit.match?(diag)
  end

  test "matches with different undefined message variant" do
    diag = %{
      severity: :error,
      message:
        "undefined function init/0 (expected Factory to define such a function or there is an optional dependency to it)",
      position: {10, 5}
    }

    assert NoModuleLevelInit.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "undefined function start/0", position: {1, 1}}
    refute NoModuleLevelInit.match?(diag)
  end

  test "ignores init with arguments" do
    diag = %{severity: :error, message: "undefined function init/1", position: {1, 1}}
    refute NoModuleLevelInit.match?(diag)
  end

  test "ignores function names ending in init" do
    diag = %{
      severity: :error,
      message: "undefined function deinit/0 (there is no such import)",
      position: {1, 1}
    }

    refute NoModuleLevelInit.match?(diag)
  end

  test "real compiler diagnostic is dispatched and repaired by the Semantic pipeline" do
    input = """
    defmodule NoModuleLevelInitCheckPipelineFixture do
      def init, do: :ok
      init()
    end
    """

    expected = """
    defmodule NoModuleLevelInitCheckPipelineFixture do
      @on_load :__credence_on_load__

      def __credence_on_load__ do
        init()
        :ok
      end

      def init, do: :ok
    end
    """

    control = """
    defmodule NoModuleLevelInitCheckPipelineControl do
      @on_load :load
      def load do
        init()
        :ok
      end
      def init, do: :ok
    end
    """

    assert {:error, diagnostics} = RuleHelpers.compile_and_capture(input)
    assert Enum.any?(diagnostics, &NoModuleLevelInit.match?/1)

    {emitted, applied} = Credence.Semantic.fix_with_trace(input)
    confirm_fix(emitted, String.trim_trailing(expected))
    assert applied == [{NoModuleLevelInit, 1}]
    assert {:ok, []} = RuleHelpers.compile_and_capture(emitted)
    assert {:ok, []} = RuleHelpers.compile_and_capture(control)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {24, 3}}
    assert NoModuleLevelInit.to_issue(diag).rule == :no_module_level_init
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {24, 3}}
    assert NoModuleLevelInit.to_issue(diag).meta.line == 24
  end

  test "passes through the diagnostic message" do
    diag = %{severity: :error, message: @real_message, position: {24, 3}}
    assert NoModuleLevelInit.to_issue(diag).message == @real_message
  end
end
