defmodule Credence.Syntax.NoMapArrowSyntaxInTupleBraceFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoMapArrowSyntaxInTupleBrace

  defp analyze(code), do: NoMapArrowSyntaxInTupleBrace.analyze(code)
  defp fix(code), do: NoMapArrowSyntaxInTupleBrace.fix(code)

  test "fixes map arrow syntax inside tuple braces" do
    input = """
    defmodule Demo do
      def body do
        Jason.encode!({"error" => "File too large", "max_bytes" => 5_242_880})
      end
    end
    """

    expected = """
    defmodule Demo do
      def body do
        Jason.encode!(%{"error" => "File too large", "max_bytes" => 5_242_880})
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes standalone arrow braces with string key" do
    confirm_fix(fix(~S'{"key" => "val"}'), ~S'%{"key" => "val"}')
  end

  test "fixes atom key arrow syntax" do
    confirm_fix(fix(~S'{:key => "val"}'), ~S'%{:key => "val"}')
  end

  test "fixed output no longer flags" do
    input = """
    defmodule Demo do
      def body do
        Jason.encode!({"error" => "File too large", "max_bytes" => 5_242_880})
      end
    end
    """

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Demo do
      def body do
        Jason.encode!({"error" => "File too large", "max_bytes" => 5_242_880})
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "fix does not mangle valid map syntax" do
    input = ~S'%{"error" => "File too large", "max_bytes" => 5_242_880}'
    confirm_fix(fix(input), input)
  end

  test "fix does not mangle valid tuple syntax" do
    input = ~S'{:ok, "result"}'
    confirm_fix(fix(input), input)
  end
end
