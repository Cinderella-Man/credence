defmodule Credence.Syntax.FixDoBlockFusionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixDoBlockFusion

  defp fix(code), do: FixDoBlockFusion.fix(code)
  defp analyze(code), do: FixDoBlockFusion.analyze(code)

  test "comma-do at end of line becomes a do block" do
    confirm_fix(
      fix("""
      defmodule Solution do
        def push(stack, value), do
          [value | stack]
        end
      end
      """),
      """
      defmodule Solution do
        def push(stack, value) do
          [value | stack]
        end
      end
      """
    )
  end

  test "doubled do opener collapses to one" do
    confirm_fix(
      fix("""
      defmodule Solution do
        def double(n) do do
          n * 2
        end
      end
      """),
      """
      defmodule Solution do
        def double(n) do
          n * 2
        end
      end
      """
    )
  end

  test "do: fused after paren with trailing end becomes a comma one-liner" do
    confirm_fix(
      fix("""
      defmodule Solution do
        def double(n) do: n * 2 end
      end
      """),
      """
      defmodule Solution do
        def double(n), do: n * 2
      end
      """
    )
  end

  test "midline comma-do gains its colon" do
    confirm_fix(
      fix("""
      defmodule Solution do
        def inc(x), do x + 1
      end
      """),
      """
      defmodule Solution do
        def inc(x), do: x + 1
      end
      """
    )
  end

  test "comma one-liner with a stray trailing end drops the end" do
    confirm_fix(
      fix("""
      defmodule Solution do
        def inc(x), do: x + 1 end
      end
      """),
      """
      defmodule Solution do
        def inc(x), do: x + 1
      end
      """
    )
  end

  # The trailing `end` here closes the inner `case` — it is NOT stray. Stripping
  # it would turn valid code into garbage, so the fix must leave it untouched.
  test "one-liner wrapping an inner do-block is left unchanged" do
    code = """
    defmodule Solution do
      def f(x), do: case y do _ -> 1 end
    end
    """

    confirm_fix(fix(code), code)
    assert valid_syntax?(code)
  end

  test "one-liner wrapping an inner fn is left unchanged" do
    code = """
    defmodule Solution do
      def f(x), do: x = fn -> 1 end
    end
    """

    confirm_fix(fix(code), code)
    assert valid_syntax?(code)
  end

  test "fix output is well-formed and analyze reaches a fixpoint" do
    code = """
    defmodule Solution do
      def double(n) do: n * 2 end
    end
    """

    assert valid_syntax?(fix(code))
    assert analyze(fix(code)) == []
  end

  # ═══════════════════════════════════════════════════════════════════
  # LITERALS — a fusion listed in "Detected patterns" is not a fusion
  #
  # All five of this rule's documented patterns are spelled out in its
  # own moduledoc heredoc, and it rewrote them (docs/22 T3.10) — the line
  # documenting `def f(x), do` came back reading `def f(x) do`, so the
  # documentation of the *input* silently became documentation of the
  # output.
  #
  # The five stages feed each other and change byte length, so the
  # `{line, shadow}` pair is threaded through the cascade with both
  # receiving the identical splice. Re-masking between stages would be
  # the `FixDivRem` defect (docs/22 T3.7): a line masked on its own
  # cannot see heredoc state that opened on an earlier line.
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/1 — only real code is rewritten" do
    test "leaves every documented pattern inside a moduledoc heredoc alone" do
      code = ~S'''
      defmodule Documented do
        @moduledoc """
        ## Detected patterns

            def f(x), do
            def f(x), do expr
            def f(x) do do
            def f(x) do: expr
            def f(x), do: expr end
        """
      end
      '''

      confirm_fix(fix(code), code)
    end

    test "leaves a fusion inside a comment alone" do
      code = "# the bug looks like: def f(x) do: expr end"

      confirm_fix(fix(code), code)
    end

    test "leaves a fusion inside a string alone" do
      code = ~S'IO.puts("emitted def f(x) do: expr end")'

      confirm_fix(fix(code), code)
    end

    test "does not report a fusion that only appears in prose" do
      code = ~S'''
      @moduledoc """
          def f(x), do
      """
      '''

      assert analyze(code) == []
    end

    test "still fixes real code in a file that also documents the broken form" do
      code = ~S'''
      defmodule Both do
        @moduledoc """
      def documented(x) do: x end
        """

        def real(x) do: x * 2 end
      end
      '''

      fixed = fix(code)

      assert fixed =~ "  def real(x), do: x * 2"
      assert fixed =~ "def documented(x) do: x end"
      assert valid_syntax?(fixed)
    end

    test "the whole cascade runs on a line that also carries a string" do
      # `) do: ` -> `), do: ` grows a byte, and the stray-`end` stage only fires
      # on what that stage produced — so this exercises the threading, not just
      # a single masked match.
      confirm_fix(
        fix(~S'def label(x) do: "a do: b end" end'),
        ~S'def label(x), do: "a do: b end"'
      )
    end

    test "the rule does not rewrite its own source file" do
      source = File.read!("lib/syntax/fix_do_block_fusion.ex")

      confirm_fix(fix(source), source)
    end
  end
end
