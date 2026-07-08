defmodule Credence.Syntax.NoPythonMultiReturnFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoPythonMultiReturn

  defp analyze(code), do: NoPythonMultiReturn.analyze(code)
  defp fix(code), do: NoPythonMultiReturn.fix(code)

  test "fixes the syntax error" do
    input = """
    defmodule BareCommaMultiReturn do
      def validate_create(nil, plan_name) do
        event = %{type: :subscription_created, plan: plan_name}
        new_state = %{plan: plan_name, status: :pending, reason: nil}
        {:ok, new_state}, [event]
      end
    end
    """

    expected = """
    defmodule BareCommaMultiReturn do
      def validate_create(nil, plan_name) do
        event = %{type: :subscription_created, plan: plan_name}
        new_state = %{plan: plan_name, status: :pending, reason: nil}
        {{:ok, new_state}, [event]}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = """
    defmodule BareCommaMultiReturn do
      def validate_create(nil, plan_name) do
        event = %{type: :subscription_created, plan: plan_name}
        new_state = %{plan: plan_name, status: :pending, reason: nil}
        {:ok, new_state}, [event]
      end
    end
    """

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule BareCommaMultiReturn do
      def validate_create(nil, plan_name) do
        event = %{type: :subscription_created, plan: plan_name}
        new_state = %{plan: plan_name, status: :pending, reason: nil}
        {:ok, new_state}, [event]
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "does not modify map keyword entries" do
    input = """
    defmodule MapKeywords do
      def build do
        name = get_name()
        %{name: name, age: 30}
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify line comments" do
    input = """
    defmodule Comments do
      # a, b, c
      def foo, do: :ok
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify catch-clause arrows" do
    input = """
    defmodule CatchClause do
      def run do
        try do
          risky()
        catch
          :exit, reason -> {:error, reason}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end
end
