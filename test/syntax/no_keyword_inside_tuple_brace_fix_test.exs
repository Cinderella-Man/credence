defmodule Credence.Syntax.NoKeywordInsideTupleBraceFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoKeywordInsideTupleBrace

  defp analyze(code), do: NoKeywordInsideTupleBrace.analyze(code)
  defp fix(code), do: NoKeywordInsideTupleBrace.fix(code)

  test "fixes keyword syntax inside tuple braces" do
    input = """
    defmodule TupleKeywordTest do
      def build_step(name, compensation) do
        %{name: name, compensation: compensation, data: [{step_name: name, compensation: compensation}]}
      end

      def build_completed(name, compensation) do
        [{step_name: name, compensation: compensation}]
      end
    end
    """

    expected = """
    defmodule TupleKeywordTest do
      def build_step(name, compensation) do
        %{name: name, compensation: compensation, data: [%{step_name: name, compensation: compensation}]}
      end

      def build_completed(name, compensation) do
        [%{step_name: name, compensation: compensation}]
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = """
    defmodule TupleKeywordTest do
      def build_step(name, compensation) do
        %{name: name, compensation: compensation, data: [{step_name: name, compensation: compensation}]}
      end

      def build_completed(name, compensation) do
        [{step_name: name, compensation: compensation}]
      end
    end
    """

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule TupleKeywordTest do
      def build_step(name, compensation) do
        %{name: name, compensation: compensation, data: [{step_name: name, compensation: compensation}]}
      end

      def build_completed(name, compensation) do
        [{step_name: name, compensation: compensation}]
      end
    end
    """

    assert valid_syntax?(fix(input))
  end
end
