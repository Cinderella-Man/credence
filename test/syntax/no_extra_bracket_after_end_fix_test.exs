defmodule Credence.Syntax.NoExtraBracketAfterEndFixTest do
  use ExUnit.Case, async: true

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoExtraBracketAfterEnd
  alias Credence.Syntax.NoUnclosedFnDelimiter

  defp analyze(code), do: NoExtraBracketAfterEnd.analyze(code)
  defp fix(code), do: NoExtraBracketAfterEnd.fix(code)

  test "removes the stray bracket" do
    input = ~S"""
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

    expected = ~S"""
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

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = ~S"""
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

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
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

    assert valid_syntax?(fix(input))
  end

  test "keeps the rest of the line when code follows the stray bracket" do
    input = ~S"""
    def f do
      x = case y do
        _ -> 1
      end] + 2
    end
    """

    expected = ~S"""
    def f do
      x = case y do
        _ -> 1
      end + 2
    end
    """

    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))
  end

  test "keeps a trailing comment on the bracket's line" do
    input = ~S"""
    def f do
      case y do
        _ -> 1
      end]  # oops
    end
    """

    expected = ~S"""
    def f do
      case y do
        _ -> 1
      end  # oops
    end
    """

    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))
  end

  test "preserves CRLF line endings byte-for-byte" do
    crlf = fn source -> String.replace(source, "\n", "\r\n") end

    input =
      crlf.(~S"""
      def f do
        case y do
          _ -> 1
        end]
      end
      """)

    expected =
      crlf.(~S"""
      def f do
        case y do
          _ -> 1
        end
      end
      """)

    confirm_fix(fix(input), expected)
  end

  # The parser reports columns in graphemes, which is what `String.split_at/2`
  # slices by — a flag, a ZWJ sequence or a precomposed accent earlier on the
  # line must not shift the cut onto the wrong character.
  test "cuts at the right character when the line holds multi-codepoint graphemes" do
    input = ~S"""
    def f do
      case y do
        _ -> "🇯🇵 👨‍👩‍👧 café" end]
    end
    """

    expected = ~S"""
    def f do
      case y do
        _ -> "🇯🇵 👨‍👩‍👧 café" end
    end
    """

    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))
  end

  test "cuts at the right character with a decomposed (combining) accent" do
    combining = "cafe" <> <<0x301::utf8>>

    input = """
    def f do
      case y do
        _ -> "#{combining}" end]
    end
    """

    expected = """
    def f do
      case y do
        _ -> "#{combining}" end
    end
    """

    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))
  end

  test "cuts at the parser column when a string starts with a combining mark" do
    input = """
    def f do
      case y do
        _ -> "́" end]
    end
    """

    expected = """
    def f do
      case y do
        _ -> "́" end
    end
    """

    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))
  end

  test "repairs its bracket while a later syntax error remains" do
    input = """
    def f do
      case :ok do
        _ -> 1
      end]
      Enum.map([], fn x -> x)
    end
    """

    intermediate =
      "def f do\n  case :ok do\n    _ -> 1\n  end\n  Enum.map([], fn x -> x)\nend\n"

    expected = """
    def f do
      case :ok do
        _ -> 1
      end
      Enum.map([], fn x -> x end)
    end
    """

    confirm_fix(fix(input), intermediate)

    emitted =
      Credence.Syntax.fix(input,
        syntax_rules: [NoExtraBracketAfterEnd, NoUnclosedFnDelimiter]
      )

    confirm_fix(emitted, expected)
    assert valid_syntax?(emitted)
  end

  test "no-op on valid code" do
    code = ~S"""
    defmodule M do
      def f do
        case :ok do
          :ok -> 1
        end
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "no-op when `end]` legitimately closes a list literal" do
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

    confirm_fix(fix(code), code)
  end

  test "no-op when the mismatched `]` does not follow an `end`" do
    code = ~S"""
    def f do
      case y do
        _ -> 1]
    end
    """

    confirm_fix(fix(code), code)
  end

  # Deliberately skipped: the real defect is a *missing* `end` and the `]`
  # closes a genuine `[`. Dropping the `]` would not make this parse, so the
  # rule leaves the source exactly as it found it.
  test "no-op when removing the bracket would not make the source parse" do
    code = ~S"""
    def f do
      x = [1, case y do
        _ -> case z do
          _ -> 3
        end]
    end
    """

    confirm_fix(fix(code), code)
  end

  test "no-op on a doubled stray bracket" do
    code = ~S"""
    def f do
      case y do
        _ -> 1
      end]]
    end
    """

    confirm_fix(fix(code), code)
  end

  test "no-op when the remainder of the line keeps the source unparseable" do
    code = ~S"""
    def f do
      x = case y do
        _ -> 1
      end], 2
    end
    """

    confirm_fix(fix(code), code)
  end

  test "no-op when the do block is closed with `}` instead of `]`" do
    code = ~S"""
    def f do
      case y do
        _ -> 1
      }
    end
    """

    confirm_fix(fix(code), code)
  end

  test "no-op on an unrelated parse error" do
    code = ~S"""
    def f do
      IO.puts("hello"
    end
    """

    confirm_fix(fix(code), code)
  end

  test "no-op on empty source" do
    confirm_fix(fix(""), "")
  end
end
