defmodule Credence.Syntax.NoExtraBracketAfterEndAnalyzeTest do
  use ExUnit.Case, async: true

  alias Credence.Issue
  alias Credence.Syntax.NoExtraBracketAfterEnd

  defp analyze(code), do: NoExtraBracketAfterEnd.analyze(code)

  test "syntax phase discovers the rule" do
    code = ~S"""
    def f do
      case y do
        _ -> 1
      end]
    end
    """

    assert [
             %Issue{
               rule: :no_extra_bracket_after_end,
               message: "Stray `]` after block-closing `end` — remove the extraneous bracket.",
               meta: %{line: 4}
             }
           ] == Credence.Syntax.analyze(code)
  end

  test "flags the unparseable code" do
    code = ~S"""
    defmodule M do
      def f do
        cond do
          true ->
            case :ok do
              :ok -> 1
            end]
        end
      end
    end
    """

    assert [%Issue{rule: :no_extra_bracket_after_end}] = analyze(code)
  end

  test "reports the line of the stray bracket" do
    code = ~S"""
    defmodule M do
      def f do
        cond do
          true ->
            case :ok do
              :ok -> 1
            end]
        end
      end
    end
    """

    assert [%Issue{meta: %{line: 7}}] = analyze(code)
  end

  test "flags a stray bracket with code following it on the same line" do
    code = ~S"""
    def f do
      x = case y do
        _ -> 1
      end] + 2
    end
    """

    assert [%Issue{rule: :no_extra_bracket_after_end}] = analyze(code)
  end

  test "leaves good code alone" do
    code = ~S"""
    defmodule M do
      def f do
        cond do
          true ->
            case :ok do
              :ok -> 1
            end
        end
      end
    end
    """

    assert analyze(code) == []
  end

  test "no issue when `end]` legitimately closes a list literal" do
    code = ~S"""
    def f do
      x = [
        1,
        case y do
          _ -> 2
        end]

      x
    end
    """

    assert analyze(code) == []
  end

  # The `]` mismatches a `do`, but is not preceded by `end` — the source is
  # missing a terminator, not carrying a stray bracket. Not this rule's job.
  test "no issue when the mismatched `]` does not follow an `end`" do
    code = ~S"""
    def f do
      case y do
        _ -> 1]
    end
    """

    assert analyze(code) == []
  end

  # Deliberately skipped: here the real defect is a *missing* `end`, and the
  # `]` closes a genuine `[`. Deleting the `]` would not make the source parse,
  # so the rule must stay silent rather than guess.
  test "no issue when removing the bracket would not make the source parse" do
    code = ~S"""
    def f do
      x = [1, case y do
        _ -> case z do
          _ -> 3
        end]
    end
    """

    assert analyze(code) == []
  end

  test "no issue on a doubled stray bracket (one removal still does not parse)" do
    code = ~S"""
    def f do
      case y do
        _ -> 1
      end]]
    end
    """

    assert analyze(code) == []
  end

  # Whatever the intent, `end], 2` is not repaired by dropping the bracket.
  test "no issue when the remainder of the line keeps the source unparseable" do
    code = ~S"""
    def f do
      x = case y do
        _ -> 1
      end], 2
    end
    """

    assert analyze(code) == []
  end

  # `}` closing a `do` belongs to Credence.Syntax.NoCaseClosedWithBrace.
  test "no issue when the do block is closed with `}` instead of `]`" do
    code = ~S"""
    def f do
      case y do
        _ -> 1
      }
    end
    """

    assert analyze(code) == []
  end

  test "no issue on an unrelated parse error" do
    code = ~S"""
    def f do
      IO.puts("hello"
    end
    """

    assert analyze(code) == []
  end

  test "no issue on empty source" do
    assert analyze("") == []
  end
end
