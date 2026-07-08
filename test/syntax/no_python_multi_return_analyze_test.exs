defmodule Credence.Syntax.NoPythonMultiReturnAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoPythonMultiReturn

  defp analyze(code), do: NoPythonMultiReturn.analyze(code)

  test "flags the unparseable code" do
    code = """
    defmodule BareCommaMultiReturn do
      def validate_create(nil, plan_name) do
        event = %{type: :subscription_created, plan: plan_name}
        new_state = %{plan: plan_name, status: :pending, reason: nil}
        {:ok, new_state}, [event]
      end
    end
    """

    assert [%Issue{rule: :no_python_multi_return, meta: %{line: 5}}] = analyze(code)
  end

  test "leaves good code alone" do
    code = """
    defmodule GoodCode do
      def validate_create(nil, plan_name) do
        event = %{type: :subscription_created, plan: plan_name}
        new_state = %{plan: plan_name, status: :pending, reason: nil}
        {{:ok, new_state}, [event]}
      end
    end
    """

    assert analyze(code) == []
  end
end
