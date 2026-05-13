defmodule Credence.Semantic.UndefinedFunctionCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.UndefinedFunction

  defp warning(msg), do: %{severity: :warning, message: msg, position: {1, 1}}

  # ── matches module.function renames ────────────────────────────

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

  # ── matches hallucinated infinity/bounds constants ─────────────

  describe "match?/1 – matches hallucinated Float infinity calls" do
    test "Float.NegInfinity/0" do
      assert UndefinedFunction.match?(warning("Float.NegInfinity/0 is undefined or private"))
    end

    test "Float.PositiveInfinity/0" do
      assert UndefinedFunction.match?(warning("Float.PositiveInfinity/0 is undefined or private"))
    end

    test "Float.NegInf/0" do
      assert UndefinedFunction.match?(warning("Float.NegInf/0 is undefined or private"))
    end

    test "Float.Infinity/0" do
      assert UndefinedFunction.match?(warning("Float.Infinity/0 is undefined or private"))
    end

    test "Float.inf/0 (lowercase, often used as -Float.inf)" do
      assert UndefinedFunction.match?(warning("Float.inf/0 is undefined or private"))
    end
  end

  describe "match?/1 – matches hallucinated Integer bounds calls" do
    test "Integer.min_value/0" do
      assert UndefinedFunction.match?(warning("Integer.min_value/0 is undefined or private"))
    end

    test "Integer.max_value/0" do
      assert UndefinedFunction.match?(warning("Integer.max_value/0 is undefined or private"))
    end
  end

  # ── matches hallucinated List operations ───────────────────────

  describe "match?/1 – matches hallucinated List calls" do
    test "List.pop/1" do
      assert UndefinedFunction.match?(warning("List.pop/1 is undefined or private"))
    end

    test "List.drop/2" do
      assert UndefinedFunction.match?(warning("List.drop/2 is undefined or private"))
    end
  end

  # ── matches wrong-module calls ─────────────────────────────────

  describe "match?/1 – matches wrong-module calls" do
    test "Enum.cycle/1 (should be Stream.cycle)" do
      assert UndefinedFunction.match?(warning("Enum.cycle/1 is undefined or private"))
    end
  end

  # ── rejects ────────────────────────────────────────────────────

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

    test "unknown Float function" do
      refute UndefinedFunction.match?(warning("Float.unknown_thing/0 is undefined or private"))
    end

    test "unknown Integer function" do
      refute UndefinedFunction.match?(warning("Integer.unknown_thing/0 is undefined or private"))
    end
  end

  # ── to_issue ───────────────────────────────────────────────────

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
