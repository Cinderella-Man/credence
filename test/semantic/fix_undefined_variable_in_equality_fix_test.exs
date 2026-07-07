defmodule Credence.Semantic.FixUndefinedVariableInEqualityFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixUndefinedVariableInEquality

  @message "undefined variable \"id\""

  defp fix(source, message, line) do
    FixUndefinedVariableInEquality.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "pre-binds undefined variable from list equality before cond" do
    input = """
    defmodule FileUpload.Router do
      defp handle_dispatch(conn) do
        cond do
          conn.method == "DELETE" and conn.path_info == ["api", "uploads", id] ->
            id
          true ->
            :ok
        end
      end
    end
    """

    expected = """
    defmodule FileUpload.Router do
      defp handle_dispatch(conn) do
        id = List.last(conn.path_info)
        cond do
          conn.method == "DELETE" and conn.path_info == ["api", "uploads", id] ->
            id
          true ->
            :ok
        end
      end
    end
    """

    confirm_fix(fix(input, @message, 4), expected)
  end

  test "uses Enum.at when variable is not the last element" do
    input = """
    defmodule Example do
      def check(items) do
        cond do
          items == [first, "b", "c"] ->
            first
          true ->
            :ok
        end
      end
    end
    """

    expected = """
    defmodule Example do
      def check(items) do
        first = Enum.at(items, 0)
        cond do
          items == [first, "b", "c"] ->
            first
          true ->
            :ok
        end
      end
    end
    """

    confirm_fix(fix(input, "undefined variable \"first\"", 4), expected)
  end

  test "handles list on the left side of equality" do
    input = """
    defmodule Example do
      def check(path) do
        cond do
          ["api", name] == path ->
            name
          true ->
            :ok
        end
      end
    end
    """

    expected = """
    defmodule Example do
      def check(path) do
        name = List.last(path)
        cond do
          ["api", name] == path ->
            name
          true ->
            :ok
        end
      end
    end
    """

    confirm_fix(fix(input, "undefined variable \"name\"", 4), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule ParseCheck do
      defp handle(conn) do
        cond do
          conn.path_info == ["api", id] ->
            id
          true ->
            :ok
        end
      end
    end
    """

    assert valid_syntax?(fix(input, @message, 4))
  end

  test "returns source unchanged when no list equality pattern found" do
    input = """
    defmodule NoMatch do
      def test do
        x + 1
      end
    end
    """

    result = fix(input, @message, 3)
    confirm_fix(result, input)
  end

  test "returns source unchanged for unrelated undefined variable" do
    input = """
    defmodule NoMatch do
      def test do
        IO.puts(y)
      end
    end
    """

    result = fix(input, "undefined variable \"y\"", 3)
    confirm_fix(result, input)
  end
end
