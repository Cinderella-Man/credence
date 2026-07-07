defmodule Credence.Semantic.NoUnreachableFunctionClauseFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoUnreachableFunctionClause

  @real_message "this clause cannot match because a previous clause at line 5 matches the same pattern as this clause"

  defp fix(source, message, line) do
    NoUnreachableFunctionClause.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 8}
    })
  end

  test "removes unreachable duplicate clause" do
    input = """
    defmodule Example do
      @moduledoc "Demonstrates duplicate function clauses that LLMs generate."

      def double_list(list), do: do_double(list, [])

      defp do_double([], acc), do: Enum.reverse(acc)
      defp do_double([h | t], acc), do: do_double(t, [h * 2 | acc])
      defp do_double([h | t], acc), do: do_double(t, [h * 3 | acc])
    end
    """

    expected = """
    defmodule Example do
      @moduledoc "Demonstrates duplicate function clauses that LLMs generate."

      def double_list(list), do: do_double(list, [])

      defp do_double([], acc), do: Enum.reverse(acc)
      defp do_double([h | t], acc), do: do_double(t, [h * 2 | acc])
    end
    """

    # The unreachable clause is at line 8 (the third do_double)
    confirm_fix(fix(input, @real_message, 8), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      @moduledoc "Demonstrates duplicate function clauses that LLMs generate."

      def double_list(list), do: do_double(list, [])

      defp do_double([], acc), do: Enum.reverse(acc)
      defp do_double([h | t], acc), do: do_double(t, [h * 2 | acc])
      defp do_double([h | t], acc), do: do_double(t, [h * 3 | acc])
    end
    """

    assert valid_syntax?(fix(input, @real_message, 8))
  end

  test "returns source unchanged when line does not match any clause" do
    input = """
    defmodule Example do
      defp do_double([], acc), do: Enum.reverse(acc)
      defp do_double([h | t], acc), do: do_double(t, [h * 2 | acc])
    end
    """

    message =
      "this clause cannot match because a previous clause at line 2 matches the same pattern as this clause"

    # Line 99 does not exist in the source
    confirm_fix(fix(input, message, 99), input)
  end
end
