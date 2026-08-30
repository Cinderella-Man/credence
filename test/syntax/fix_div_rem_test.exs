defmodule Credence.Syntax.FixDivRemTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixDivRem

  describe "analyze/1" do
    test "detects infix div" do
      source = """
      defmodule Example do
        def half(n), do: n div 2
      end
      """

      issues = FixDivRem.analyze(source)
      assert length(issues) == 1
      assert hd(issues).rule == :infix_div
      assert hd(issues).message =~ "div"
    end

    test "detects infix rem" do
      source = """
      defmodule Example do
        def odd?(n), do: n rem 2 != 0
      end
      """

      issues = FixDivRem.analyze(source)
      assert length(issues) == 1
      assert hd(issues).rule == :infix_rem
    end

    test "detects div in complex expression" do
      source = """
      defmodule Example do
        def gauss(n) do
          n * (n + 1) div 2
        end
      end
      """

      issues = FixDivRem.analyze(source)
      assert length(issues) == 1
    end

    test "detects multiple infix operators" do
      source = """
      defmodule Example do
        def compute(a, b) do
          x = a div b
          y = a rem b
          {x, y}
        end
      end
      """

      issues = FixDivRem.analyze(source)
      assert length(issues) == 2
      rules = Enum.map(issues, & &1.rule) |> Enum.sort()
      assert rules == [:infix_div, :infix_rem]
    end

    test "no issues for valid function call syntax" do
      source = """
      defmodule Example do
        def half(n), do: div(n, 2)
        def remainder(n), do: rem(n, 2)
      end
      """

      assert FixDivRem.analyze(source) == []
    end

    test "no issues for pipe syntax" do
      source = """
      defmodule Example do
        def half(n), do: n |> div(2)
      end
      """

      assert FixDivRem.analyze(source) == []
    end

    test "detects infix rem inside capture" do
      source = """
      defmodule Example do
        def check(list) do
          Enum.map(list, &(&1 rem 2 == 0))
        end
      end
      """

      issues = FixDivRem.analyze(source)
      assert length(issues) == 1
      assert hd(issues).rule == :infix_rem
    end

    test "no issues for div in comments" do
      source = """
      defmodule Example do
        # use div to divide
        def half(n), do: div(n, 2)
      end
      """

      assert FixDivRem.analyze(source) == []
    end
  end

  describe "fix/1" do
    test "fixes simple infix div" do
      source = "x = a div b"

      expected = "x = div(a, b)"

      confirm_fix(FixDivRem.fix(source), expected)
    end

    test "fixes simple infix rem" do
      source = "x = a rem b"

      expected = "x = rem(a, b)"

      confirm_fix(FixDivRem.fix(source), expected)
    end

    test "fixes div with assignment" do
      source = """
      defmodule Example do
        def half(n) do
          result = n div 2
          result
        end
      end
      """

      expected = """
      defmodule Example do
        def half(n) do
          result = div(n, 2)
          result
        end
      end
      """

      confirm_fix(FixDivRem.fix(source), expected)
    end

    test "fixes complex left operand" do
      source = """
      defmodule Example do
        def gauss(n) do
          expected_sum = n * (n + 1) div 2
          expected_sum
        end
      end
      """

      expected = """
      defmodule Example do
        def gauss(n) do
          expected_sum = div(n * (n + 1), 2)
          expected_sum
        end
      end
      """

      confirm_fix(FixDivRem.fix(source), expected)
    end

    test "fixes both div and rem in same file" do
      source = """
      defmodule Example do
        def compute(a, b) do
          x = a div b
          y = a rem b
          {x, y}
        end
      end
      """

      expected = """
      defmodule Example do
        def compute(a, b) do
          x = div(a, b)
          y = rem(a, b)
          {x, y}
        end
      end
      """

      confirm_fix(FixDivRem.fix(source), expected)
    end

    test "does not modify valid function call syntax" do
      source = """
      defmodule Example do
        def half(n), do: div(n, 2)
      end
      """

      confirm_fix(FixDivRem.fix(source), source)
    end

    test "does not rewrite infix rem inside capture" do
      source = """
      defmodule Example do
        def check(list) do
          Enum.map(list, &(&1 rem 2 == 0))
        end
      end
      """

      confirm_fix(FixDivRem.fix(source), source)
    end

    test "does not modify pipe syntax" do
      source = """
      defmodule Example do
        def half(n), do: n |> div(2)
      end
      """

      confirm_fix(FixDivRem.fix(source), source)
    end

    test "fixed code produces valid Elixir" do
      source = """
      defmodule FixDivTest do
        def gauss(n) do
          n * (n + 1) div 2
        end
      end
      """

      fixed = FixDivRem.fix(source)
      assert valid_syntax?(fixed)
    end

    test "fix reaches a fixpoint — fixed output no longer flags" do
      source = "x = a div b"

      assert FixDivRem.analyze(FixDivRem.fix(source)) == []
    end

    test "fix output is well-formed (parses)" do
      assert valid_syntax?(
               FixDivRem.fix("""
               x = a div b
               """)
             )
    end

    test "does not mangle div inside function call arguments" do
      source = """
          moves_minus = do_minto1((n - 1) div 2, 0)
          moves_plus = do_minto1((n + 1) div 2, 0)
      """

      expected = """
          moves_minus = do_minto1(Kernel.div((n - 1), 2), 0)
          moves_plus = do_minto1(Kernel.div((n + 1), 2), 0)
      """

      confirm_fix(FixDivRem.fix(source), expected)
    end

    test "fixed code with function args produces valid Elixir" do
      source = """
      defmodule KernelDivTest do
        def minto1(n) do
          moves_minus = do_minto1((n - 1) div 2, 0)
          moves_plus = do_minto1((n + 1) div 2, 0)
          min(moves_minus, moves_plus)
        end

        defp do_minto1(1, moves), do: moves
        defp do_minto1(n, moves), do: do_minto1(div(n, 2), moves + 1)
      end
      """

      fixed = FixDivRem.fix(source)
      assert valid_syntax?(fixed)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FUNCTION HEADS
  #
  # `def f(n), do: <expr> div 2` used to have its entire head swallowed
  # by the lazy left-operand group. The result was not merely broken:
  # FixKeywordBeforePositionalArgument, later in the same reduce,
  # reshaped it into something that PARSED, so the phase logged success
  # and shipped a completely different program.
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/1 — keyword-body function heads" do
    test "fixes infix div inside a nested keyword body" do
      confirm_fix(
        FixDivRem.fix("def f, do: if ok, do: a div b"),
        "def f, do: if ok, do: div(a, b)"
      )

      emitted =
        FixDivRem.fix(
          "defmodule FixDivRemNestedKeywordEmitted do\n" <>
            "  def f(ok, a, b), do: if ok, do: a div b\nend"
        )

      control = """
      defmodule FixDivRemNestedKeywordControl do
        def f(ok, a, b), do: if(ok, do: div(a, b))
      end

      unless FixDivRemNestedKeywordEmitted.f(true, 7, 2) ==
               FixDivRemNestedKeywordControl.f(true, 7, 2),
        do: raise("nested keyword repair changed the result")
      """

      assert {:ok, [%{severity: :warning}]} =
               Credence.RuleHelpers.compile_and_capture(emitted <> "\n" <> control)
    end

    test "fixes a def head with a compound left operand" do
      confirm_fix(
        FixDivRem.fix("def f(n), do: n * (n + 1) div 2"),
        "def f(n), do: div(n * (n + 1), 2)"
      )
    end

    test "fixes a defp head" do
      confirm_fix(FixDivRem.fix("defp f(n), do: n div 2"), "defp f(n), do: div(n, 2)")
    end

    test "fixes a head with several arguments" do
      confirm_fix(FixDivRem.fix("def f(n, m), do: n div m"), "def f(n, m), do: div(n, m)")
    end

    test "fixes a head carrying a when guard" do
      confirm_fix(
        FixDivRem.fix("def f(n) when n > 0, do: n div 2"),
        "def f(n) when n > 0, do: div(n, 2)"
      )
    end

    test "the def-head repair survives the whole syntax phase" do
      source = "def f(n), do: n * (n + 1) div 2"
      fixed = Credence.Syntax.fix(source)

      confirm_fix(fixed, "def f(n), do: div(n * (n + 1), 2)")
      assert valid_syntax?(fixed)
    end
  end

  describe "fix/1 — right operand boundaries" do
    test "does not absorb a following addition into the divisor" do
      confirm_fix(FixDivRem.fix("x = a div b + 1"), "x = div(a, b) + 1")

      emitted =
        FixDivRem.fix(
          "defmodule FixDivRemRightBoundaryEmitted do\n" <>
            "  def f(a, b), do: a div b + 1\nend"
        )

      control = """
      defmodule FixDivRemRightBoundaryControl do
        def f(a, b), do: div(a, b) + 1
      end

      unless FixDivRemRightBoundaryEmitted.f(7, 2) ==
               FixDivRemRightBoundaryControl.f(7, 2),
        do: raise("right operand repair changed precedence")
      """

      assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(emitted <> "\n" <> control)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # LITERALS — `div`/`rem` named in prose is not an operator
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/1 — string literals are not code" do
    test "leaves a string that mentions the operator alone" do
      source = ~S'IO.puts("use a div b now")'
      confirm_fix(FixDivRem.fix(source), source)
    end

    test "does not report a string that mentions the operator" do
      assert FixDivRem.analyze(~s|IO.puts("use a div b now")|) == []
    end

    test "leaves the string alone end-to-end while fixing real code" do
      source = """
      defmodule Report do
        def render(pct) do
          IO.puts("use a div b for integer division")
          n = 10 div 2
          {pct, n}
        end
      end
      """

      expected = """
      defmodule Report do
        def render(pct) do
          IO.puts("use a div b for integer division")
          n = div(10, 2)
          {pct, n}
        end
      end
      """

      confirm_fix(Credence.Syntax.fix(source), expected)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MULTI-LINE LITERALS — a line cannot be masked on its own
  #
  # `analyze` has always masked the whole file; `fix` masked each line in
  # isolation, where a heredoc body reads as pure code. The two disagreed,
  # so the rule rewrote what it had never reported — including its own
  # moduledoc. Found by running every Syntax rule's `fix/1` over its own
  # source file.
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/1 — heredoc bodies are not code" do
    test "leaves a heredoc body that mentions the operator alone" do
      source = """
      defmodule Doc do
        @moduledoc \"\"\"
        expected_sum = n * (n + 1) div 2
        \"\"\"
        def f(x), do: x
      end
      """

      confirm_fix(FixDivRem.fix(source), source)
    end

    test "does not report a heredoc body — and never did" do
      source = """
      defmodule Doc do
        @moduledoc \"\"\"
        expected_sum = n * (n + 1) div 2
        \"\"\"
        def f(x), do: x
      end
      """

      assert FixDivRem.analyze(source) == []
    end

    test "still fixes real code below a heredoc that mentions the operator" do
      source = """
      defmodule Doc do
        @moduledoc \"\"\"
        expected_sum = n * (n + 1) div 2
        \"\"\"
        def f(n), do: n div 2
      end
      """

      expected = """
      defmodule Doc do
        @moduledoc \"\"\"
        expected_sum = n * (n + 1) div 2
        \"\"\"
        def f(n), do: div(n, 2)
      end
      """

      confirm_fix(FixDivRem.fix(source), expected)
    end

    test "the rule does not rewrite its own source file" do
      source = File.read!("lib/syntax/fix_div_rem.ex")

      confirm_fix(FixDivRem.fix(source), source)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # STATEMENT AND FUNCTION BOUNDARIES
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/1 — statement and function boundaries" do
    test "fixes an infix operator after an earlier statement" do
      source = ~S'IO.puts("a div b"); x = n div 2'
      expected = ~S'IO.puts("a div b"); x = div(n, 2)'
      emitted = FixDivRem.fix(source)

      confirm_fix(emitted, expected)

      program = """
      defmodule FixDivRemStatementBoundaryEmitted do
        def f(n) do
          #{emitted}
          x
        end
      end

      defmodule FixDivRemStatementBoundaryControl do
        def f(n) do
          IO.puts("a div b")
          x = div(n, 2)
          x
        end
      end

      unless FixDivRemStatementBoundaryEmitted.f(7) ==
               FixDivRemStatementBoundaryControl.f(7),
        do: raise("statement-boundary repair changed the result")
      """

      assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(program)
    end

    test "fixes an infix operator in an anonymous function body" do
      emitted = FixDivRem.fix("fn n -> n div 2 end")
      confirm_fix(emitted, "fn n -> div(n, 2) end")

      program = """
      defmodule FixDivRemAnonymousFunctionEmitted do
        def f, do: (#{emitted}).(7)
      end

      defmodule FixDivRemAnonymousFunctionControl do
        def f, do: (fn n -> div(n, 2) end).(7)
      end

      unless FixDivRemAnonymousFunctionEmitted.f() == FixDivRemAnonymousFunctionControl.f(),
        do: raise("anonymous-function repair changed the result")
      """

      assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(program)
    end
  end
end
