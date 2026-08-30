defmodule Credence.Syntax.NoCaseClosedWithBraceFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoCaseClosedWithBrace

  defp analyze(code), do: NoCaseClosedWithBrace.analyze(code)
  defp fix(code), do: NoCaseClosedWithBrace.fix(code)

  test "replaces the mismatched } with end" do
    input = """
    defmodule FixDoClosedWithBrace do
      def transform(state) do
        Map.put(state, :result, case Map.get(state, :val) do
          nil -> state
          v -> %{state | data: v}
        })
      end
    end
    """

    expected = """
    defmodule FixDoClosedWithBrace do
      def transform(state) do
        Map.put(state, :result, case Map.get(state, :val) do
          nil -> state
          v -> %{state | data: v}
        end)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "repairs every do block closed with a brace" do
    input = """
    case :first do
      _ -> :first
    }
    case :second do
      _ -> :second
    }
    """

    expected = """
    case :first do
      _ -> :first
    end
    case :second do
      _ -> :second
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "uses parser codepoint columns when replacing the brace" do
    input = """
    case :value do
      _ -> é; }
    """

    expected = """
    case :value do
      _ -> é; end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = """
    defmodule FixDoClosedWithBrace do
      def transform(state) do
        Map.put(state, :result, case Map.get(state, :val) do
          nil -> state
          v -> %{state | data: v}
        })
      end
    end
    """

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule FixDoClosedWithBrace do
      def transform(state) do
        Map.put(state, :result, case Map.get(state, :val) do
          nil -> state
          v -> %{state | data: v}
        })
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "leaves properly closed code untouched" do
    source = """
    defmodule Good do
      def transform(state) do
        Map.put(state, :result, case Map.get(state, :val) do
          nil -> state
          v -> %{state | data: v}
        end)
      end
    end
    """

    confirm_fix(fix(source), source)
  end

  test "leaves a different mismatched delimiter untouched" do
    source = "value = [1, 2, 3)"

    confirm_fix(fix(source), source)
  end

  test "fix clears the analyze flag (fixpoint)" do
    input = """
    defmodule FixDoClosedWithBrace do
      def transform(state) do
        Map.put(state, :result, case Map.get(state, :val) do
          nil -> state
          v -> %{state | data: v}
        })
      end
    end
    """

    assert analyze(fix(input)) == []
  end
end
