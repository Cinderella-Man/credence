defmodule Credence.Semantic.NoShadowedFunctionRedefinitionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoShadowedFunctionRedefinition

  @real_message "this clause cannot match because a previous clause at line 2 always matches"

  defp fix(source, message, line) do
    NoShadowedFunctionRedefinition.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 3}
    })
  end

  test "removes the earlier shadowed definition" do
    input = """
    defmodule ShadowedRedef do
      def process(data) do
        {:draft, data}
      end

      def helper(x), do: x * 2

      def process(data) do
        {:ok, helper(data)}
      end
    end
    """

    expected = """
    defmodule ShadowedRedef do
      def helper(x), do: x * 2

      def process(data) do
        {:ok, helper(data)}
      end
    end
    """

    confirm_fix(fix(input, @real_message, 8), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule ShadowedRedef do
      def process(data) do
        {:draft, data}
      end

      def helper(x), do: x * 2

      def process(data) do
        {:ok, helper(data)}
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message, 8))
  end

  test "returns source unchanged when line does not match any clause" do
    input = """
    defmodule Example do
      def foo(x), do: x
    end
    """

    message = "this clause cannot match because a previous clause at line 99 always matches"
    confirm_fix(fix(input, message, 5), input)
  end
end
