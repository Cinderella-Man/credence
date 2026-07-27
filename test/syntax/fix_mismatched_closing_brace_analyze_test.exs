defmodule Credence.Syntax.FixMismatchedClosingBraceAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixMismatchedClosingBrace

  defp analyze(code), do: FixMismatchedClosingBrace.analyze(code)

  test "flags a list bracket replaced with brace before a tuple closer" do
    source = ~S"""
    defmodule M do
      def f do
        {a, [b, c}, d}
      end
    end
    """

    assert [%Issue{rule: :fix_mismatched_closing_brace}] = analyze(source)
  end

  test "flags the LLM reduce/tuple mismatch from the spec" do
    source = ~S"""
    defmodule MismatchedBrace do
      def transform(data) do
        Enum.reduce(data, {[], [], %{}}, fn x, {ok, fail, stats} ->
          case x do
            :fail ->
              {ok, [%{reason: x} | stats[:failures] || []}, stats}
          end
        end)
      end
    end
    """

    assert [%Issue{rule: :fix_mismatched_closing_brace}] = analyze(source)
  end

  test "leaves valid code alone" do
    source = ~S"""
    defmodule M do
      def f do
        {a, [b, c], d}
      end
    end
    """

    assert analyze(source) == []
  end

  test "leaves code with unclosed brace (different rule) alone" do
    # This is a different pattern (unclosed {, not mismatched [ })
    source = ~S"""
    defmodule M do
      def f do
        {:ok, %{key: "value"}
      end
    end
    """

    assert analyze(source) == []
  end
end
