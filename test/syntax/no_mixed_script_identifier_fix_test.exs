defmodule Credence.Syntax.NoMixedScriptIdentifierFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoMixedScriptIdentifier

  defp analyze(code), do: NoMixedScriptIdentifier.analyze(code)
  defp fix(code), do: NoMixedScriptIdentifier.fix(code)

  test "fixes the syntax error by removing the mixed-script defmodule" do
    input = """
    defmodule Saga do
      def hello, do: :world
    end

    defmodule补偿State do
      def hello, do: :world
    end
    """

    expected = """
    defmodule Saga do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(fix("""
           defmodule Saga do
             def hello, do: :world
           end

           defmodule补偿State do
             def hello, do: :world
           end
           """)) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix("""
           defmodule Saga do
             def hello, do: :world
           end

           defmodule补偿State do
             def hello, do: :world
           end
           """))
  end

  test "leaves already-clean source unchanged" do
    input = """
    defmodule Saga do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input), input)
  end
end
