defmodule Credence.Syntax.FixPythonFloorDivTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixPythonFloorDiv

  defp analyze(code), do: FixPythonFloorDiv.analyze(code)
  defp fix(code), do: FixPythonFloorDiv.fix(code)

  # ═══════════════════════════════════════════════════════════════════
  # analyze/1 — what is flagged
  # ═══════════════════════════════════════════════════════════════════

  describe "analyze/1 flags floor division" do
    test "infix word // word" do
      issues =
        analyze("def half(n), do: n // 2")

      assert length(issues) == 1
      assert hd(issues).rule == :python_floor_div
      assert hd(issues).meta == %{line: 1}
    end

    test "Kernel.// in pipe" do
      source = """
      defmodule Example do
        def step(acc, k) do
          acc
          |> Kernel.//(k)
          |> next()
        end
      end
      """

      issues = analyze(source)
      assert length(issues) == 1
      assert hd(issues).rule == :python_floor_div
    end

    test "Kernel.// standalone call" do
      assert length(analyze("def divide(a, b), do: Kernel.//(a, b)")) == 1
    end
  end

  describe "analyze/1 — deliberately NOT flagged (dropped from the safe core)" do
    # A parenthesised left operand cannot be rewritten safely without a parser,
    # so it is left untouched. check and fix agree: neither touches it.
    test "no issue for `(expr) // n` (complex left operand)" do
      source = """
      defmodule Example do
        def gauss(n) do
          result = n * (n + 1) // 2
          result
        end
      end
      """

      assert analyze(source) == []
    end

    test "no issue for valid div/2 call" do
      assert analyze("def half(n), do: div(n, 2)") == []
    end

    test "no issue for pipe into div" do
      assert analyze("def half(n), do: n |> div(2)") == []
    end

    test "no issue for // inside a comment" do
      source = """
      defmodule Example do
        # use integer division (// in Python)
        def half(n), do: div(n, 2)
      end
      """

      assert analyze(source) == []
    end

    test "no issue for Kernel./ float division" do
      assert analyze("def half(n), do: Kernel./(n, 2)") == []
    end

    test "no issue for range step 0..-2//1" do
      assert analyze("Enum.slice(list, 0..-2//1)") == []
    end

    test "no issue for range step 1..10//2" do
      assert analyze("Enum.to_list(1..10//2)") == []
    end

    test "no issue for range step with variable bounds n..m//-1" do
      assert analyze("Enum.to_list(n..m//-1)") == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # fix/1 — exact whole-string rewrites
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/1 rewrites word // word to div" do
    test "n // 2" do
      confirm_fix(fix("n // 2"), "div(n, 2)")
    end

    test "no spaces n//2" do
      confirm_fix(fix("n//2"), "div(n, 2)")
    end

    test "integer // integer" do
      confirm_fix(fix("100 // 7"), "div(100, 7)")
    end

    test "in assignment" do
      confirm_fix(fix("x = a // b"), "x = div(a, b)")
    end
  end

  describe "fix/1 preserves surrounding code (local swap)" do
    test "one-liner def head" do
      confirm_fix(fix("def half(n), do: n // 2"), "def half(n), do: div(n, 2)")
    end

    test "comparison / guard context" do
      confirm_fix(fix("if n // 2 == 0 do"), "if div(n, 2) == 0 do")
    end

    test "preserves indentation" do
      confirm_fix(fix("      n // 2"), "      div(n, 2)")
    end

    test "only touches lines with floor division" do
      input = """
      defmodule Example do
        def foo(x), do: x + 1
        def bar(n), do: n // 2
        def baz(y), do: y - 1
      end
      """

      expected = """
      defmodule Example do
        def foo(x), do: x + 1
        def bar(n), do: div(n, 2)
        def baz(y), do: y - 1
      end
      """

      confirm_fix(fix(input), expected)
    end
  end

  describe "fix/1 rewrites Kernel.//" do
    test "standalone call" do
      confirm_fix(fix("result = Kernel.//(a, b)"), "result = div(a, b)")
    end

    test "in pipe" do
      input = """
      defmodule Example do
        def step(acc, k) do
          acc
          |> Kernel.//(k)
          |> next()
        end
      end
      """

      expected = """
      defmodule Example do
        def step(acc, k) do
          acc
          |> div(k)
          |> next()
        end
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "the exact pattern from the row log — only Kernel.// is touched" do
      input = """
      defp do_combination(n, k, acc) do
        acc
        |> Kernel.*(n - k + 1)
        |> Kernel.//(k)
        |> do_combination(n, k - 1)
      end
      """

      expected = """
      defp do_combination(n, k, acc) do
        acc
        |> Kernel.*(n - k + 1)
        |> div(k)
        |> do_combination(n, k - 1)
      end
      """

      confirm_fix(fix(input), expected)
    end
  end

  describe "fix/1 leaves valid and dropped cases untouched" do
    test "complex left operand `(expr) // n` is a no-op" do
      code = """
      defmodule Example do
        def gauss(n) do
          result = n * (n + 1) // 2
          result
        end
      end
      """

      confirm_fix(fix(code), code)
    end

    test "valid div/2 call unchanged" do
      code = """
      defmodule Example do
        def half(n), do: div(n, 2)
      end
      """

      confirm_fix(fix(code), code)
    end

    test "pipe into div unchanged" do
      code = """
      defmodule Example do
        def half(n), do: n |> div(2)
      end
      """

      confirm_fix(fix(code), code)
    end

    test "comment with // unchanged" do
      code = """
      defmodule Example do
        # integer division // for Python users
        def half(n), do: div(n, 2)
      end
      """

      confirm_fix(fix(code), code)
    end

    test "range step 0..-2//1 unchanged" do
      code = "middle = Enum.slice(list, 0..-2//1)"

      confirm_fix(fix(code), code)
    end

    test "range step 1..10//2 unchanged" do
      code = "evens = Enum.to_list(1..10//2)"

      confirm_fix(fix(code), code)
    end

    test "range step with variable bounds unchanged" do
      code = "Enum.reduce(n..m//-1, 0, fn i, acc -> i + acc end)"

      confirm_fix(fix(code), code)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # round-trip — fixed code no longer flags
  # ═══════════════════════════════════════════════════════════════════

  describe "round-trip" do
    test "fixed code produces zero analyze issues" do
      code = """
      def half(n), do: n // 2
      def step(acc, k), do: acc |> Kernel.//(k)
      """

      assert analyze(fix(code)) == []
    end
  end

  describe "fix output is well-formed" do
    test "fixed output parses" do
      assert valid_syntax?(fix("n // 2"))
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # LITERALS — a `//` inside a string is prose, not an operator
  #
  # Every case below shipped corrupted. The outputs parsed AND compiled,
  # so nothing downstream noticed the program had started printing
  # something the author never wrote. The whole-line `^\s*#` guard this
  # rule used to carry caught only a line that *began* with a comment —
  # a trailing one was rewritten along with the code.
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/1 — string literals are not code" do
    test "leaves a path inside a string alone" do
      code = ~S'IO.puts("ratio 7 // 2 here")'

      confirm_fix(fix(code), code)
    end

    test "leaves the string alone while still fixing real code on the same line" do
      confirm_fix(
        fix(~S'IO.puts("path//to//file"); x = a // b'),
        ~S'IO.puts("path//to//file"); x = div(a, b)'
      )
    end

    test "fixes inside interpolation — that IS code" do
      confirm_fix(fix(~S'IO.puts("#{a // b}")'), ~S'IO.puts("#{div(a, b)}")')
    end

    test "leaves an uppercase sigil alone — it does not interpolate" do
      code = ~S'IO.puts(~S(raw a // b))'

      confirm_fix(fix(code), code)
    end

    test "leaves a charlist alone" do
      code = ~S'x = ~c"ratio a // b"'

      confirm_fix(fix(code), code)
    end

    test "leaves a heredoc body alone" do
      code = ~S'''
      @moduledoc """
      integer division is a // b in Python
      """
      '''

      confirm_fix(fix(code), code)
    end

    test "leaves a trailing comment alone while fixing the code before it" do
      confirm_fix(fix("x = a // b  # was a // b"), "x = div(a, b)  # was a // b")
    end

    test "a range step inside a string no longer declines the whole line" do
      confirm_fix(
        fix(~S'IO.puts("slice 0..-2//1"); x = a // b'),
        ~S'IO.puts("slice 0..-2//1"); x = div(a, b)'
      )
    end

    test "does not report a string-only //" do
      assert analyze(~S'IO.puts("ratio 7 // 2 here")') == []
    end

    test "does not report a trailing-comment-only //" do
      assert analyze("x = div(a, b)  # was a // b") == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # END-TO-END through the syntax phase
  # ═══════════════════════════════════════════════════════════════════

  describe "integration through Credence.Syntax" do
    test "repairs the floor division without touching the path string" do
      source = """
      defmodule FloorDivInteg do
        def render(n) do
          IO.puts("ratio 7 // 2 here")
          n // 2
        end
      end
      """

      expected = """
      defmodule FloorDivInteg do
        def render(n) do
          IO.puts("ratio 7 // 2 here")
          div(n, 2)
        end
      end
      """

      fixed = Credence.Syntax.fix(source)
      confirm_fix(fixed, expected)
      assert valid_syntax?(fixed)
    end
  end
end
