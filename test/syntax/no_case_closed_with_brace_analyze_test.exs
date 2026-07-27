defmodule Credence.Syntax.NoCaseClosedWithBraceAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoCaseClosedWithBrace

  defp analyze(code), do: NoCaseClosedWithBrace.analyze(code)

  test "flags a case block closed with } instead of end" do
    code = """
    defmodule FixDoClosedWithBrace do
      def transform(state) do
        Map.put(state, :result, case Map.get(state, :val) do
          nil -> state
          v -> %{state | data: v}
        })
      end
    end
    """

    assert [%Issue{rule: :no_case_closed_with_brace, meta: %{line: 6}}] = analyze(code)
  end

  test "reports the line of the offending }" do
    code = """
    def foo do
      case x do
        nil -> :ok
      }
    end
    """

    assert [%Issue{rule: :no_case_closed_with_brace, meta: %{line: 4}}] = analyze(code)
  end

  test "leaves properly closed code alone" do
    code = """
    defmodule Good do
      def transform(state) do
        Map.put(state, :result, case Map.get(state, :val) do
          nil -> state
          v -> %{state | data: v}
        end)
      end
    end
    """

    assert analyze(code) == []
  end

  test "does not flag a different mismatched delimiter" do
    # `[` closed by `)` — a real mismatch, but not a do/brace one.
    assert analyze("value = [1, 2, 3)") == []
  end

  test "does not flag fn closed with ) instead of end" do
    # fn closed by `)` — owned by NoUnclosedFnDelimiter.
    assert analyze("list |> Enum.max_by(fn {_, second} -> second)") == []
  end

  test "does not flag valid code" do
    assert analyze("""
           def foo do
             42
           end
           """) == []
  end
end
