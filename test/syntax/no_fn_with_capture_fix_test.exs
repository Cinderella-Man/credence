defmodule Credence.Syntax.NoFnWithCaptureFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoFnWithCapture

  defp fix(code), do: NoFnWithCapture.fix(code)
  defp analyze(code), do: NoFnWithCapture.analyze(code)

  test "rewrites fn( to &( before a capture variable" do
    input = "Enum.filter(list, fn(&1 > 0))"

    expected = "Enum.filter(list, &(&1 > 0))"

    confirm_fix(fix(input), expected)
  end

  test "fixes the call inside a module" do
    input = """
    defmodule Solution do
      def filter_positives(list) do
        Enum.filter(list, fn(&1 > 0))
      end
    end
    """

    expected = """
    defmodule Solution do
      def filter_positives(list) do
        Enum.filter(list, &(&1 > 0))
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "preserves later capture variables in the body" do
    input = "Enum.reduce(list, fn(&1 + &2))"

    expected = "Enum.reduce(list, &(&1 + &2))"

    confirm_fix(fix(input), expected)
  end

  test "leaves valid parenthesised fn parameters untouched" do
    source = "Enum.filter(list, fn(x) -> x > 0 end)"

    confirm_fix(fix(source), source)
  end

  test "leaves an identifier that merely ends in fn untouched" do
    source = "myfn(&1 > 0)"

    confirm_fix(fix(source), source)
  end

  test "leaves a comment line untouched but fixes real code on other lines" do
    input = """
    # keep this: Enum.filter(list, fn(&1 > 0))
    Enum.filter(list, fn(&1 > 0))
    """

    expected = """
    # keep this: Enum.filter(list, fn(&1 > 0))
    Enum.filter(list, &(&1 > 0))
    """

    confirm_fix(fix(input), expected)
  end

  test "fix clears the analyze flag (fixpoint)" do
    assert analyze(fix("Enum.filter(list, fn(&1 > 0))")) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             defmodule Solution do
               def filter_positives(list) do
                 Enum.filter(list, fn(&1 > 0))
               end
             end
             """)
           )
  end

  # ═══════════════════════════════════════════════════════════════════
  # LITERALS — knowing about the class is not being guarded against it
  #
  # This rule already carried a guard, and a comment saying that
  # rewriting non-code content "would corrupt" it. The guard only skipped
  # lines starting with `#`, so it protected comments and missed heredocs
  # entirely: three sentences of this rule's own moduledoc prose were
  # rewritten from naming the broken form to naming the fixed one
  # (docs/22 T3.10). Matching now runs against a `Credence.SourceMask`
  # shadow, which covers the whole class the original comment described.
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/1 — only real code is rewritten" do
    test "leaves the malformed form named in moduledoc prose alone" do
      code = ~S'''
      defmodule Documented do
        @moduledoc """
        LLMs repeatedly emit `fn(&1 > 0)`, gluing the `fn` keyword onto a capture.
        """
      end
      '''

      confirm_fix(fix(code), code)
    end

    test "leaves the malformed form inside a comment alone" do
      code = "# LLMs emit fn(&1 > 0) here"

      confirm_fix(fix(code), code)
    end

    test "leaves the malformed form inside a string alone" do
      code = ~S'IO.puts("the bug looks like fn(&1 > 0)")'

      confirm_fix(fix(code), code)
    end

    test "does not report a mention that only appears in prose" do
      code = ~S'''
      @moduledoc """
      so `fn(&1 ...)` never parses
      """
      '''

      assert analyze(code) == []
    end

    test "leaves the string alone while still fixing real code on the same line" do
      confirm_fix(
        fix(~S'IO.puts("bug: fn(&1 > 0)"); Enum.filter(l, fn(&1 > 0))'),
        ~S'IO.puts("bug: fn(&1 > 0)"); Enum.filter(l, &(&1 > 0))'
      )
    end

    test "the rule does not rewrite its own source file" do
      source = File.read!("lib/syntax/no_fn_with_capture.ex")

      confirm_fix(fix(source), source)
    end
  end
end
