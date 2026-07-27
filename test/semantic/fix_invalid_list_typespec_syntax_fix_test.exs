defmodule Credence.Semantic.FixInvalidListTypespecSyntaxFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixInvalidListTypespecSyntax

  @message "credence_check.ex:6: unexpected list in typespec: [integer(), integer()]"

  defp fix(source, message, line) do
    FixInvalidListTypespecSyntax.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes the source" do
    input = """
    defmodule Solution do
      @spec has_path(num_nodes :: non_neg_integer(), edges :: list([integer(), integer()]), source :: integer(), destination :: integer()) :: boolean()
      def has_path(num_nodes, edges, source, destination) do
        true
      end
    end
    """

    expected = """
    defmodule Solution do
      @spec has_path(num_nodes :: non_neg_integer(), edges :: [[integer(), integer()]], source :: integer(), destination :: integer()) :: boolean()
      def has_path(num_nodes, edges, source, destination) do
        true
      end
    end
    """

    confirm_fix(fix(input, @message, 2), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Solution do
      @spec has_path(num_nodes :: non_neg_integer(), edges :: list([integer(), integer()]), source :: integer(), destination :: integer()) :: boolean()
      def has_path(num_nodes, edges, source, destination) do
        true
      end
    end
    """

    assert valid_syntax?(fix(input, @message, 2))
  end

  test "returns source unchanged when line has no list([)" do
    source = """
    defmodule M do
      @spec foo(x :: integer()) :: boolean()
      def foo(x), do: true
    end
    """

    confirm_fix(fix(source, @message, 2), source)
  end

  test "returns source unchanged when position is nil" do
    source = "some code"
    bad_diag = %{severity: :error, message: @message, position: nil}
    confirm_fix(FixInvalidListTypespecSyntax.fix(source, bad_diag), source)
  end
end
