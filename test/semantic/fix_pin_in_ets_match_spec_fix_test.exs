defmodule Credence.Semantic.FixPinInEtsMatchSpecFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixPinInEtsMatchSpec

  @message "misplaced operator ^name\n\nThe pin operator ^ is supported only inside matches or inside custom macros. Make sure you are inside a match or all necessary macros have been required"

  defp message(var) do
    "misplaced operator ^#{var}\n\nThe pin operator ^ is supported only inside matches or inside custom macros. Make sure you are inside a match or all necessary macros have been required"
  end

  # The compiler reports the exact {line, column} of the offending `^`
  # (column 32 for the `:ets.match_delete(table, {{^name, …` fixtures below).
  defp fix(source, message \\ @message, position \\ {3, 32}) do
    FixPinInEtsMatchSpec.fix(source, %{severity: :error, message: message, position: position})
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

    confirm_fix(fix(input, message("name"), {3, 32}), expected)
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

    confirm_fix(fix(input, message("n"), {3, 32}), expected)
  end

  test "strips pin from a guard, where a bare variable has the same meaning" do
    input = """
    defmodule GuardPin do
      def g(x, y) when ^y > 0, do: x
    end
    """

    expected = """
    defmodule GuardPin do
      def g(x, y) when y > 0, do: x
    end
    """

    confirm_fix(fix(input, message("y"), {2, 20}), expected)
  end

  test "leaves a valid pin in a match context on the same line untouched" do
    input = """
    defmodule T2 do
      def go(t, k, x) do
        if match?({^k, _}, x), do: :ets.match_delete(t, {^k, :_})
      end
    end
    """

    # The compiler flags only the second `^k` (column 54); the pin inside
    # `match?/2` (column 16) is a valid match-context pin and must survive.
    expected = """
    defmodule T2 do
      def go(t, k, x) do
        if match?({^k, _}, x), do: :ets.match_delete(t, {k, :_})
      end
    end
    """

    confirm_fix(fix(input, message("k"), {3, 54}), expected)
  end

  test "strips only the pin at the diagnostic column when two invalid pins share a line" do
    input = """
    defmodule TwoPins do
      def go(t, a, b) do
        :ets.match_delete(t, {^a, ^b})
      end
    end
    """

    expected = """
    defmodule TwoPins do
      def go(t, a, b) do
        :ets.match_delete(t, {a, ^b})
      end
    end
    """

    confirm_fix(fix(input, message("a"), {3, 27}), expected)
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

  test "returns source unchanged when the column points at no pin" do
    input = """
    defmodule FixPinInEtsMatchSpec do
      def reset(table, name) do
        :ets.match_delete(table, {{^name, :_}, :_})
      end
    end
    """

    confirm_fix(fix(input, @message, {3, 5}), input)
  end

  test "returns source unchanged when the pin at the column has a different name" do
    input = """
    defmodule FixPinInEtsMatchSpec do
      def reset(table, nome) do
        :ets.match_delete(table, {{^nome, :_}, :_})
      end
    end
    """

    confirm_fix(fix(input, message("name"), {3, 32}), input)
  end

  test "returns source unchanged when the position carries no column" do
    input = """
    defmodule FixPinInEtsMatchSpec do
      def reset(table, name) do
        :ets.match_delete(table, {{^name, :_}, :_})
      end
    end
    """

    confirm_fix(fix(input, @message, 3), input)
  end
end
