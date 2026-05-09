defmodule Credence.Semantic.UndefinedFunctionCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.UndefinedFunction

  defp warning(msg), do: %{severity: :warning, message: msg, position: {1, 1}}

  describe "match?/1 – matches undefined functions" do
    test "Enum.last/1" do
      assert UndefinedFunction.match?(warning("Enum.last/1 is undefined or private"))
    end

    test "Enum.last/0" do
      assert UndefinedFunction.match?(warning("Enum.last/0 is undefined or private"))
    end

    test "List.reverse/1" do
      assert UndefinedFunction.match?(warning("List.reverse/1 is undefined or private"))
    end
  end

  describe "match?/1 – matches deprecated functions" do
    test "Enum.partition/2" do
      assert UndefinedFunction.match?(
               warning("Enum.partition/2 is deprecated. Use Enum.split_with/2 instead")
             )
    end
  end

  describe "match?/1 – rejects" do
    test "unknown function" do
      refute UndefinedFunction.match?(warning("MyModule.foo/2 is undefined or private"))
    end

    test "unknown deprecated function" do
      refute UndefinedFunction.match?(
               warning("MyModule.old_func/1 is deprecated. Use MyModule.new_func/1 instead")
             )
    end

    test "unrelated warning" do
      refute UndefinedFunction.match?(warning("some other warning"))
    end

    test "error severity" do
      refute UndefinedFunction.match?(%{
               severity: :error,
               message: "Enum.last/1 is undefined or private",
               position: {1, 1}
             })
    end
  end

  describe "to_issue/1" do
    test "extracts rule and line" do
      issue =
        UndefinedFunction.to_issue(%{
          severity: :warning,
          message: "Enum.last/1 is undefined or private",
          position: {10, 5}
        })

      assert issue.rule == :undefined_function
      assert issue.meta.line == 10
    end
  end
end
