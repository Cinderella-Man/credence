defmodule Credence.Semantic.UndefinedFunctionCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.UndefinedFunction

  defp warning(msg), do: %{severity: :warning, message: msg, position: {1, 1}}
  defp error(msg), do: %{severity: :error, message: msg, position: {1, 1}}

  defp local_matches?(name, arity) do
    UndefinedFunction.match?(
      error(
        "undefined function #{name}/#{arity} (expected MyModule to define such a function or for it to be imported, but none are available)"
      )
    )
  end

  # ── qualified: known replacements ──────────────────────────────

  describe "match?/1 – qualified: renames" do
    test "Enum.last/1" do
      assert UndefinedFunction.match?(warning("Enum.last/1 is undefined or private"))
    end

    test "Enum.last/0" do
      assert UndefinedFunction.match?(warning("Enum.last/0 is undefined or private"))
    end

    test "List.reverse/1" do
      assert UndefinedFunction.match?(warning("List.reverse/1 is undefined or private"))
    end

    test "List.second/1" do
      assert UndefinedFunction.match?(warning("List.second/1 is undefined or private"))
    end

    test "Enum.take_last/2" do
      assert UndefinedFunction.match?(warning("Enum.take_last/2 is undefined or private"))
    end
  end

  describe "match?/1 – qualified: deprecated" do
    test "Enum.partition/2" do
      assert UndefinedFunction.match?(
               warning("Enum.partition/2 is deprecated. Use Enum.split_with/2 instead")
             )
    end
  end

  describe "match?/1 – qualified: Float infinity" do
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

    test "Float.inf/0" do
      assert UndefinedFunction.match?(warning("Float.inf/0 is undefined or private"))
    end
  end

  describe "match?/1 – qualified: Integer bounds" do
    test "Integer.min_value/0" do
      assert UndefinedFunction.match?(warning("Integer.min_value/0 is undefined or private"))
    end

    test "Integer.max_value/0" do
      assert UndefinedFunction.match?(warning("Integer.max_value/0 is undefined or private"))
    end
  end

  describe "match?/1 – qualified: List + wrong-module" do
    test "List.pop/1" do
      assert UndefinedFunction.match?(warning("List.pop/1 is undefined or private"))
    end

    test "List.drop/2" do
      assert UndefinedFunction.match?(warning("List.drop/2 is undefined or private"))
    end

    test "Enum.cycle/1" do
      assert UndefinedFunction.match?(warning("Enum.cycle/1 is undefined or private"))
    end
  end

  describe "match?/1 – qualified: FunctionMatcher fallback" do
    test "any module.function undefined" do
      assert UndefinedFunction.match?(warning("MyModule.foo/2 is undefined or private"))
    end

    test "PalindromeChecker.palindrome/1" do
      assert UndefinedFunction.match?(
               warning("PalindromeChecker.palindrome/1 is undefined or private")
             )
    end
  end

  describe "match?/1 – qualified: rejects" do
    test "unrelated warning" do
      refute UndefinedFunction.match?(warning("some other warning"))
    end

    test "error severity for qualified" do
      refute UndefinedFunction.match?(%{
               severity: :error,
               message: "Enum.last/1 is undefined or private",
               position: {1, 1}
             })
    end

    test "no parseable function ref" do
      refute UndefinedFunction.match?(warning("something is undefined or private"))
    end
  end

  # ── local: known replacements ──────────────────────────────────

  describe "match?/1 – local: infinity" do
    test "infinity/0" do
      assert local_matches?("infinity", 0)
    end
  end

  describe "match?/1 – local: max/min" do
    test "max/1" do
      assert local_matches?("max", 1)
    end

    test "max/3" do
      assert local_matches?("max", 3)
    end

    test "max/4" do
      assert local_matches?("max", 4)
    end

    test "max/5" do
      assert local_matches?("max", 5)
    end

    test "min/1" do
      assert local_matches?("min", 1)
    end

    test "min/3" do
      assert local_matches?("min", 3)
    end

    test "min/4" do
      assert local_matches?("min", 4)
    end

    test "min/5" do
      assert local_matches?("min", 5)
    end
  end

  describe "match?/1 – local: Python built-ins" do
    test "sum/1" do
      assert local_matches?("sum", 1)
    end

    test "sorted/1" do
      assert local_matches?("sorted", 1)
    end

    test "len/1" do
      assert local_matches?("len", 1)
    end

    test "reversed/1" do
      assert local_matches?("reversed", 1)
    end
  end

  describe "match?/1 – local: range" do
    test "range/1" do
      assert local_matches?("range", 1)
    end

    test "range/2" do
      assert local_matches?("range", 2)
    end

    test "range/3" do
      assert local_matches?("range", 3)
    end
  end

  describe "match?/1 – local: FunctionMatcher fallback" do
    test "fibonacci/1" do
      assert local_matches?("fibonacci", 1)
    end

    test "while/2" do
      assert local_matches?("while", 2)
    end

    test "foobar/0" do
      assert local_matches?("foobar", 0)
    end

    test "max/2" do
      assert local_matches?("max", 2)
    end

    test "range/0" do
      assert local_matches?("range", 0)
    end

    test "range/4" do
      assert local_matches?("range", 4)
    end
  end

  describe "match?/1 – local: rejects" do
    test "warning severity for local" do
      refute UndefinedFunction.match?(%{
               severity: :warning,
               message:
                 "undefined function infinity/0 (expected MyModule to define such a function)",
               position: {1, 1}
             })
    end

    test "unrelated error" do
      refute UndefinedFunction.match?(error("some other error"))
    end

    test "error without 'undefined function'" do
      refute UndefinedFunction.match?(error("something went wrong with foo/1"))
    end
  end

  # ── to_issue ───────────────────────────────────────────────────

  describe "to_issue/1" do
    test "qualified diagnostic" do
      issue =
        UndefinedFunction.to_issue(%{
          severity: :warning,
          message: "Enum.last/1 is undefined or private",
          position: {10, 5}
        })

      assert issue.rule == :undefined_function
      assert issue.meta.line == 10
    end

    test "local diagnostic" do
      issue =
        UndefinedFunction.to_issue(%{
          severity: :error,
          message: "undefined function infinity/0 (expected MyModule to define such a function)",
          position: {19, 76}
        })

      assert issue.rule == :undefined_function
      assert issue.meta.line == 19
    end
  end
end
