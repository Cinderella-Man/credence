defmodule Credence.Semantic.FixPinInEtsMatchSpecFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixPinInEtsMatchSpec

  @message "misplaced operator ^name\n\nThe pin operator ^ is supported only inside matches or inside custom macros. Make sure you are inside a match or all necessary macros have been required"

  defp fix(source, message \\ @message, line \\ 3) do
    FixPinInEtsMatchSpec.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  test "strips pin operator from match_delete call" do
    input = """
    defmodule FixPinInEtsMatchSpec do
      def reset(table, name) do
        :ets.match_delete(table, {{^name, :_}, :_})
      end
    end
    """

    expected = """
    defmodule FixPinInEtsMatchSpec do
      def reset(table, name) do
        :ets.match_delete(table, {{name, :_}, :_})
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "strips pin operator from match_object call" do
    input = """
    defmodule FindByName do
      def find(table, name) do
        :ets.match_object(table, {{^name, :_}, :_})
      end
    end
    """

    expected = """
    defmodule FindByName do
      def find(table, name) do
        :ets.match_object(table, {{name, :_}, :_})
      end
    end
    """

    message = "misplaced operator ^name\n\nThe pin operator ^ is supported only inside matches or inside custom macros."
    confirm_fix(fix(input, message, 3), expected)
  end

  test "strips pin operator with short variable name" do
    input = """
    defmodule ShortVar do
      def reset(table, n) do
        :ets.match_delete(table, {{^n, :_}, :_})
      end
    end
    """

    expected = """
    defmodule ShortVar do
      def reset(table, n) do
        :ets.match_delete(table, {{n, :_}, :_})
      end
    end
    """

    message = "misplaced operator ^n\n\nThe pin operator ^ is supported only inside matches or inside custom macros."
    confirm_fix(fix(input, message, 3), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule FixPinInEtsMatchSpec do
      def reset(table, name) do
        :ets.match_delete(table, {{^name, :_}, :_})
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "returns source unchanged when no pin on target line" do
    input = """
    defmodule FixPinInEtsMatchSpec do
      def reset(table, name) do
        :ets.match_delete(table, {{name, :_}, :_})
      end
    end
    """

    confirm_fix(fix(input), input)
  end
end
