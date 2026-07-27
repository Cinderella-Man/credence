defmodule Credence.Semantic.NoCaptureAsBitwiseAndFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoCaptureAsBitwiseAnd

  @real_message "capture argument &1 must be used within the capture operator &"

  defp diag(line, col) do
    %{severity: :error, message: @real_message, position: {line, col}}
  end

  describe "fix/2 — column-targeted" do
    test "rewrites IDENT & INTEGER to Bitwise.band/2" do
      source = """
      defmodule M do
        def f(n) do
          n & 1
        end
      end
      """

      expected = """
      defmodule M do
        def f(n) do
          Bitwise.band(n, 1)
        end
      end
      """

      confirm_fix(NoCaptureAsBitwiseAnd.fix(source, diag(3, 7)), expected)
    end

    test "keeps the surrounding text on the line intact" do
      source = """
      defmodule M do
        def low?(n) do
          if (n & 1) == 1, do: :yes, else: :no
        end
      end
      """

      expected = """
      defmodule M do
        def low?(n) do
          if (Bitwise.band(n, 1)) == 1, do: :yes, else: :no
        end
      end
      """

      confirm_fix(NoCaptureAsBitwiseAnd.fix(source, diag(3, 11)), expected)
    end

    test "handles multi-digit literal and extra whitespace" do
      source = """
      defmodule M do
        def f(count) do
          count   &   2
        end
      end
      """

      expected = """
      defmodule M do
        def f(count) do
          Bitwise.band(count, 2)
        end
      end
      """

      confirm_fix(NoCaptureAsBitwiseAnd.fix(source, diag(3, 11)), expected)
    end

    test "rewrites only the flagged & and leaves a legit capture on the line intact" do
      source = """
      defmodule M do
        def f(l, n), do: Enum.map(l, &foo/1) ++ [n & 1]
      end
      """

      expected = """
      defmodule M do
        def f(l, n), do: Enum.map(l, &foo/1) ++ [Bitwise.band(n, 1)]
      end
      """

      confirm_fix(NoCaptureAsBitwiseAnd.fix(source, diag(2, 44)), expected)
    end

    test "only rewrites the flagged line" do
      source = """
      defmodule M do
        def a(x), do: x & 1
        def b(y), do: y & 1
      end
      """

      expected = """
      defmodule M do
        def a(x), do: Bitwise.band(x, 1)
        def b(y), do: y & 1
      end
      """

      confirm_fix(NoCaptureAsBitwiseAnd.fix(source, diag(2, 19)), expected)
    end
  end

  describe "fix/2 — bare integer position (fallback)" do
    test "rewrites the first match on the flagged line" do
      source = """
      defmodule M do
        def f(n), do: n & 1
      end
      """

      expected = """
      defmodule M do
        def f(n), do: Bitwise.band(n, 1)
      end
      """

      diag = %{severity: :error, message: @real_message, position: 2}
      confirm_fix(NoCaptureAsBitwiseAnd.fix(source, diag), expected)
    end
  end

  describe "fix/2 — no-ops" do
    test "returns source unchanged when position is nil" do
      source = "n & 1"

      diag = %{severity: :error, message: @real_message, position: nil}
      confirm_fix(NoCaptureAsBitwiseAnd.fix(source, diag), source)
    end

    test "returns source unchanged when flagged line has no match" do
      source = """
      defmodule M do
        def f, do: :ok
      end
      """

      confirm_fix(NoCaptureAsBitwiseAnd.fix(source, diag(2, 14)), source)
    end
  end

  describe "fix output is well-formed" do
    test "fixed output parses" do
      source = """
      defmodule M do
        def f(n) do
          n & 1
        end
      end
      """

      assert valid_syntax?(NoCaptureAsBitwiseAnd.fix(source, diag(3, 7)))
    end
  end

  describe "integration through Credence.Semantic" do
    test "fixes `x & 1` end-to-end and the result compiles" do
      source = """
      defmodule CaptureAndFixInteg1 do
        def low_bit(n) do
          n & 1
        end
      end
      """

      expected = """
      defmodule CaptureAndFixInteg1 do
        def low_bit(n) do
          Bitwise.band(n, 1)
        end
      end
      """

      fixed = Credence.Semantic.fix(source)
      confirm_fix(fixed, expected)
      assert valid_syntax?(fixed)
    end

    test "leaves correct Bitwise.band code untouched" do
      source = """
      defmodule CaptureAndFixInteg2 do
        def low_bit(n) do
          Bitwise.band(n, 1)
        end
      end
      """

      confirm_fix(Credence.Semantic.fix(source), source)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # INTEGER LITERAL FORMS
  #
  # Only bare decimal digits used to be accepted, so the right operand
  # was cut at the `0` of every non-decimal literal — i.e. exactly the
  # literals bitmask code is normally written with.
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/2 — every integer literal form" do
    test "hex" do
      confirm_fix(
        NoCaptureAsBitwiseAnd.fix("flags & 0xFF", diag(1, 7)),
        "Bitwise.band(flags, 0xFF)"
      )
    end

    test "lowercase hex" do
      confirm_fix(
        NoCaptureAsBitwiseAnd.fix("flags & 0xff", diag(1, 7)),
        "Bitwise.band(flags, 0xff)"
      )
    end

    test "binary" do
      confirm_fix(
        NoCaptureAsBitwiseAnd.fix("mask & 0b1010", diag(1, 6)),
        "Bitwise.band(mask, 0b1010)"
      )
    end

    test "octal" do
      confirm_fix(NoCaptureAsBitwiseAnd.fix("x & 0o17", diag(1, 3)), "Bitwise.band(x, 0o17)")
    end

    test "underscore-separated decimal" do
      confirm_fix(
        NoCaptureAsBitwiseAnd.fix("flags & 1_000", diag(1, 7)),
        "Bitwise.band(flags, 1_000)"
      )
    end

    test "every form produces output that parses" do
      for {src, col} <- [{"flags & 0xFF", 7}, {"mask & 0b1010", 6}, {"x & 0o17", 3}] do
        assert valid_syntax?(NoCaptureAsBitwiseAnd.fix(src, diag(1, col)))
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DECLINED SHAPES
  #
  # Python's `&` binds looser than every arithmetic operator, so these
  # operands are whole expressions. Rewriting them yields code that
  # COMPILES and returns a different number — strictly worse than the
  # compile error the source already has.
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/2 — declines what it cannot group correctly" do
    test "declines an arithmetic left operand (the Python hash idiom)" do
      source = "h * 31 + c & 0xFFFFFFFF"
      confirm_fix(NoCaptureAsBitwiseAnd.fix(source, diag(1, 12)), source)
    end

    test "declines a multiplicative left operand" do
      confirm_fix(NoCaptureAsBitwiseAnd.fix("a * b & 0xFF", diag(1, 7)), "a * b & 0xFF")
    end

    test "declines an arithmetic right operand" do
      confirm_fix(NoCaptureAsBitwiseAnd.fix("flags & 0xFF + 1", diag(1, 7)), "flags & 0xFF + 1")
    end

    test "declines a dotted chain" do
      confirm_fix(NoCaptureAsBitwiseAnd.fix("m.flags & 0xFF", diag(1, 9)), "m.flags & 0xFF")
    end

    test "declines a module attribute chain" do
      confirm_fix(
        NoCaptureAsBitwiseAnd.fix("@state.flags & 0xFF", diag(1, 14)),
        "@state.flags & 0xFF"
      )
    end

    test "declines an Erlang remote call" do
      source = ":erlang.system_time & 0xFF"
      confirm_fix(NoCaptureAsBitwiseAnd.fix(source, diag(1, 21)), source)
    end

    test "declines a unary minus on a chain" do
      confirm_fix(NoCaptureAsBitwiseAnd.fix("-m.flags & 0xFF", diag(1, 10)), "-m.flags & 0xFF")
    end

    test "declines a non-ASCII identifier rather than splicing into it" do
      confirm_fix(NoCaptureAsBitwiseAnd.fix("naïve & 0xFF", diag(1, 8)), "naïve & 0xFF")
    end

    test "declines a float right operand" do
      confirm_fix(NoCaptureAsBitwiseAnd.fix("n & 2.0", diag(1, 3)), "n & 2.0")
    end
  end

  describe "fix/2 — string literals are not code" do
    test "leaves an `&` inside a string alone" do
      source = ~S'IO.puts("mask & 1") && g(m)'
      confirm_fix(NoCaptureAsBitwiseAnd.fix(source, diag(1, 15)), source)
    end
  end
end
