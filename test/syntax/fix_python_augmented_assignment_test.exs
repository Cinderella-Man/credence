defmodule Credence.Syntax.FixPythonAugmentedAssignmentTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixPythonAugmentedAssignment
  alias Credence.RuleHelpers

  defp analyze(code), do: FixPythonAugmentedAssignment.analyze(code)
  defp fix(code), do: FixPythonAugmentedAssignment.fix(code)

  describe "analyze/1 — flags bare-variable augmented assignment" do
    test "detects += on a simple variable" do
      source = """
      defmodule Example do
        def run(count) do
          count += 1
        end
      end
      """

      issues = analyze(source)
      assert length(issues) == 1
      assert hd(issues).rule == :python_augmented_assignment
      assert hd(issues).meta.line == 3
    end

    test "detects += with a complex right-hand side" do
      source = """
      defp count_prefix_sums(prefix_counts, current_sum, count, [head | tail], goal) do
        count += Map.get(prefix_counts, new_sum - goal, 0)
      end
      """

      assert length(analyze(source)) == 1
    end

    test "detects -=" do
      assert length(analyze("value -= delta")) == 1
    end

    test "detects *=" do
      assert length(analyze("total *= factor")) == 1
    end

    test "detects /=" do
      assert length(analyze("value /= divisor")) == 1
    end

    test "detects multiple augmented assignments across lines" do
      source = """
      defmodule Example do
        def run(a, b) do
          a += 1
          b -= 2
        end
      end
      """

      assert length(analyze(source)) == 2
    end
  end

  describe "analyze/1 — does NOT flag (safety choices locked in)" do
    test "comment lines" do
      source = """
      defmodule Example do
        # x += 1 is Python syntax
        def run(x), do: x
      end
      """

      assert analyze(source) == []
    end

    test "code without augmented assignment" do
      assert analyze("y = x + 1") == []
    end

    test "operator inside a string literal" do
      assert analyze(~S'x = "a += b"') == []

      assert analyze(~S'msg = "5/=2 ratio"') == []
    end

    test "qualified (dotted) left-hand side — cannot be rebound" do
      assert analyze("socket.assigns.count += 1") == []
    end

    test "indexed left-hand side — not a bare variable" do
      assert analyze("arr[i] += 1") == []
    end

    test "augmented op that is not the leading statement" do
      assert analyze("z = a += b") == []
    end

    test "no right-hand side" do
      assert analyze("x += ") == []
    end
  end

  describe "fix/1 — bare-variable rewrites (RHS parenthesised)" do
    test "+= selects Elixir concatenation for literal lists and strings" do
      cases = [
        {"items += [1]", "items = items ++ ([1])", "[0]", "[0, 1]"},
        {~S|text += "x"|, ~S|text = text <> ("x")|, ~S|"a"|, ~S|"ax"|}
      ]

      for {input, expected, initial, result} <- cases do
        emitted = fix(input)
        confirm_fix(emitted, expected)

        actual =
          "unless (fn #{variable(input)} -> #{emitted}; #{variable(input)} end).(#{initial}) == #{result}, do: raise(\"wrong result\")"

        control =
          "unless (fn #{variable(input)} -> #{expected}; #{variable(input)} end).(#{initial}) == #{result}, do: raise(\"wrong result\")"

        assert RuleHelpers.compile_and_capture(actual) ==
                 RuleHelpers.compile_and_capture(control)
      end
    end

    test "fixes += with simple variable" do
      confirm_fix(fix("count += 1"), "count = count + (1)")
    end

    test "fixes += with no surrounding spaces" do
      confirm_fix(fix("x+=1"), "x = x + (1)")
    end

    test "fixes += with a complex right-hand side" do
      confirm_fix(
        fix("count += Map.get(prefix_counts, new_sum - goal, 0)"),
        "count = count + (Map.get(prefix_counts, new_sum - goal, 0))"
      )
    end

    test "fixes -= with simple variable" do
      confirm_fix(fix("value -= delta"), "value = value - (delta)")
    end

    test "fixes *= with simple variable" do
      confirm_fix(fix("total *= factor"), "total = total * (factor)")
    end

    test "fixes /= with simple variable" do
      confirm_fix(fix("value /= divisor"), "value = value / (divisor)")
    end

    test "preserves leading indentation" do
      confirm_fix(fix("    count += 1"), "    count = count + (1)")
    end

    test "fixes multiple augmented assignments across lines" do
      source = """
      a += 1
      b -= 2
      """

      expected = """
      a = a + (1)
      b = b - (2)
      """

      confirm_fix(fix(source), expected)
    end

    test "the exact pattern from the row log" do
      source = """
      defp count_prefix_sums(prefix_counts, current_sum, count, [head | tail], goal) do
        new_sum = current_sum + head
        count += Map.get(prefix_counts, new_sum - goal, 0)
        count_prefix_sums(prefix_counts, new_sum, count, tail, goal)
      end
      """

      expected = """
      defp count_prefix_sums(prefix_counts, current_sum, count, [head | tail], goal) do
        new_sum = current_sum + head
        count = count + (Map.get(prefix_counts, new_sum - goal, 0))
        count_prefix_sums(prefix_counts, new_sum, count, tail, goal)
      end
      """

      confirm_fix(fix(source), expected)
    end
  end

  defp variable(input), do: input |> String.split() |> hd()

  describe "fix/1 — parenthesising keeps Python operator precedence" do
    # Python `x *= 3 + 4` means `x = x * (3 + 4)` (== 14), NOT `x = x * 3 + 4`
    # (== 10). The naive unparenthesised rewrite would change the answer.
    test "*= with a lower-precedence right-hand side" do
      confirm_fix(fix("x *= 3 + 4"), "x = x * (3 + 4)")
    end

    test "-= with a subtraction right-hand side" do
      confirm_fix(fix("x -= 3 - 1"), "x = x - (3 - 1)")
    end

    test "/= with a lower-precedence right-hand side" do
      confirm_fix(fix("x /= a + b"), "x = x / (a + b)")
    end

    test "-= with a negative literal" do
      confirm_fix(fix("x -= -1"), "x = x - (-1)")
    end
  end

  describe "fix/1 — no-ops (must not corrupt valid code)" do
    test "comment line unchanged" do
      code = "# x += 1 is Python"

      confirm_fix(fix(code), code)
    end

    test "code without augmented assignment unchanged" do
      code = "y = x + 1"

      confirm_fix(fix(code), code)
    end

    test "operator inside a string literal unchanged" do
      code = ~S'x = "a += b"'

      confirm_fix(fix(code), code)
    end

    test "string literal containing /= unchanged" do
      code = ~S'msg = "5/=2 ratio"'

      confirm_fix(fix(code), code)
    end

    test "qualified left-hand side unchanged" do
      code = "socket.assigns.count += 1"

      confirm_fix(fix(code), code)
    end

    test "indexed left-hand side unchanged" do
      code = "arr[i] += 1"

      confirm_fix(fix(code), code)
    end

    test "augmented op not leading the statement unchanged" do
      code = "z = a += b"

      confirm_fix(fix(code), code)
    end
  end

  describe "round-trip" do
    test "fixed code parses and produces zero analyze issues" do
      code = """
      defmodule Example do
        def run(count) do
          count += 1
          count *= 3 + 4
        end
      end
      """

      fixed = fix(code)
      assert valid_syntax?(fixed)
      assert analyze(fixed) == []
    end

    test "fix reaches a fixpoint — fixed output no longer flags" do
      assert analyze(fix("count += 1")) == []
    end

    test "fix output is well-formed (parses)" do
      assert valid_syntax?(fix("count += 1"))
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # LITERALS — an augmented assignment shown in a doc is not one
  #
  # The moduledoc's "Not flagged" list argued that a string literal is
  # safe because the `op=` is "not the line's leading token". True of
  # `x = "a += b"`, and irrelevant inside a heredoc, where a
  # documentation line may begin with exactly this shape — as all four
  # of this rule's own examples did (docs/22 T3.10).
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/1 — only real code is rewritten" do
    test "leaves an augmented assignment inside a moduledoc heredoc alone" do
      code = ~S'''
      defmodule Documented do
        @moduledoc """
        ## Bad

            count += Map.get(freq, key, 0)
            total *= factor
        """
      end
      '''

      confirm_fix(fix(code), code)
    end

    test "leaves an augmented assignment inside a comment alone" do
      code = "# count += 1"

      confirm_fix(fix(code), code)
    end

    test "does not report an assignment that only appears in prose" do
      code = ~S'''
      @moduledoc """
          total *= factor
      """
      '''

      assert analyze(code) == []
    end

    test "still fixes real code in a file that also documents the broken form" do
      code = ~S'''
      defmodule Both do
        @moduledoc """
      documented += 1
        """

        def go(count) do
          count += 1
          count
        end
      end
      '''

      fixed = fix(code)

      assert fixed =~ "    count = count + (1)"
      assert fixed =~ "documented += 1"
      assert valid_syntax?(fixed)
    end

    test "the rule does not rewrite its own source file" do
      source = File.read!("lib/syntax/fix_python_augmented_assignment.ex")

      confirm_fix(fix(source), source)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # TRAILING COMMENTS — the closing paren must not land inside one
  #
  # A second defect, found while converting this rule and confirmed by
  # running it: the right-hand side ran to the end of the line, so a
  # trailing comment was captured as part of the expression and the
  # emitted `)` landed inside it. The output did not parse at all.
  # The shadow settles it — a comment is blanked to the line's end, and
  # the raw byte at the start of that run separates a comment from a
  # trailing string, which IS part of the expression.
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/1 — the expression ends where the comment starts" do
    test "keeps the comment after the rewritten statement" do
      confirm_fix(
        fix("count += 1  # running total"),
        "count = count + (1)  # running total"
      )
    end

    test "output parses when a trailing comment follows a call" do
      fixed = fix("count += Map.get(freq, key, 0) # lookup")

      confirm_fix(fixed, "count = count + (Map.get(freq, key, 0)) # lookup")
      assert valid_syntax?(fixed)
    end

    test "a `#` inside a string is not a comment" do
      confirm_fix(fix(~S'msg += "a # b"'), ~S'msg = msg <> ("a # b")')
    end

    test "a trailing string stays in the expression and its comment does not" do
      fixed = fix(~S'msg += "abc"  # trailing note')

      confirm_fix(fixed, ~S'msg = msg <> ("abc")  # trailing note')
      assert valid_syntax?(fixed)
    end

    test "a line that is only an assignment to a comment is declined" do
      code = "count += # nothing here"

      confirm_fix(fix(code), code)
    end
  end
end
