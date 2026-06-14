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
end
