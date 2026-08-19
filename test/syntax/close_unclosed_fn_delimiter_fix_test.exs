defmodule Credence.Syntax.CloseUnclosedFnDelimiterFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Issue
  alias Credence.Syntax.CloseUnclosedFnDelimiter
  alias Credence.Syntax.NoUnclosedFnDelimiter

  defp analyze(code), do: CloseUnclosedFnDelimiter.analyze(code)
  defp fix(code), do: CloseUnclosedFnDelimiter.fix(code)

  # A genuine occurrence of this rule's shape plus an unrelated broken call
  # below it. Two tests share it — the repair itself, and the re-fix-your-own-
  # output check at the bottom of the file, which needs *this* source because
  # its repair is the one that leaves an unparseable leftover behind. Written
  # once here so the two cannot drift apart.
  @local_source """
  defmodule Local do
    def go(m) do
      Enum.map(m, fn r ->
        Enum.map(r, fn e ->
          if e == 0 do 1 else e end)
        end
      end)
    end

    def broken(, do: 1
  end
  """

  # The realistic occurrence of this rule's shape and its repair. Three tests
  # share it — the repair itself, and the two that check what the repaired
  # output is (it no longer flags, and it parses). Written once so an edit to
  # the input cannot leave the other two asserting about a different program.
  @solution_source """
  defmodule Solution do
    def replace_zero(matrix) do
      Enum.map(matrix, fn row ->
        non_zeros = Enum.filter(row, fn element -> element != 0 end)
        case non_zeros do
          [] -> row
          _ ->
            min_value = Enum.min(non_zeros)
            Enum.map(row, fn element ->
              if element == 0 do min_value else element end)
            end
        end
      end)
    end
  end
  """

  @solution_repaired """
  defmodule Solution do
    def replace_zero(matrix) do
      Enum.map(matrix, fn row ->
        non_zeros = Enum.filter(row, fn element -> element != 0 end)
        case non_zeros do
          [] -> row
          _ ->
            min_value = Enum.min(non_zeros)
            Enum.map(row, fn element ->
              if element == 0 do min_value else element end end)
        end
      end)
    end
  end
  """

  # One copy of the same bug in a whole module, and its repair. Two tests stack
  # two copies of it — the repair of both, and the line numbers reported for
  # them — and the second's expected lines (5 and 14) are arithmetic on this
  # exact source, so the two must be the same bytes by construction.
  @two_bugs """
  defmodule TwoBugs do
    def a(m) do
      Enum.map(m, fn r ->
        Enum.map(r, fn e ->
          if e == 0 do 1 else e end)
        end
      end)
    end
  end
  """

  @two_bugs_repaired """
  defmodule TwoBugs do
    def a(m) do
      Enum.map(m, fn r ->
        Enum.map(r, fn e ->
          if e == 0 do 1 else e end end)
      end)
    end
  end
  """

  # The smallest whole occurrence of the bug, and its repair. The two pass-bound
  # tests below stack a hundred-odd copies of it, so it is kept short.
  @one_occurrence """
  Enum.map(m, fn r ->
    Enum.map(r, fn e -> if e == 0 do 1 else e end)
    end
  end)
  """

  @one_occurrence_repaired """
  Enum.map(m, fn r ->
    Enum.map(r, fn e -> if e == 0 do 1 else e end end)
  end)
  """

  test "inserts missing end before ) and removes stray end on next line" do
    confirm_fix(fix(@solution_source), @solution_repaired)
  end

  test "fixed output no longer flags" do
    assert analyze(fix(@solution_source)) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix(@solution_source))
  end

  test "does not modify already-valid code" do
    code = "Enum.map(list, fn x -> x end)"

    confirm_fix(fix(code), code)
  end

  test "leaves a plain unclosed fn untouched (NoUnclosedFnDelimiter owns it)" do
    code = "list |> Enum.max_by(fn {_, second} -> second)"

    confirm_fix(fix(code), code)
  end

  # Not a masking test, despite the docstring: the parser's first complaint
  # about this file is the unrelated `def broken(` on line 7 being closed by the
  # module's own `end` — opening delimiter `(`, not `fn` — so `detect/1` returns
  # `:none` and the rule hands the source back without examining a single line.
  # Replacing the docstring's contents, or deleting the `@moduledoc` outright,
  # gives the identical no-op, so the docstring is not what is being tested
  # here; the short-circuit is. The one test where the mask genuinely does the
  # work is the `Heredoc` one below, whose downward `end`-token scan is the only
  # place in this file that runs over a shadow.
  test "declines outright when the parser's first complaint is not an fn closed by )" do
    input = """
    defmodule M do
      @moduledoc \"\"\"
          Enum.map(row, fn element ->
            if element == 0 do a else element end)
          end
      \"\"\"
      def broken(, do: 1
    end
    """

    confirm_fix(fix(input), input)
    assert analyze(input) == []
  end

  # The repair is local: it must not wait for the whole file to parse. Two copies
  # of this same bug in one file used to be repaired not at all — each candidate
  # deletion for copy 1 still failed to parse because of copy 2, so the rule
  # returned the source byte-identical and reported nothing.
  test "repairs both occurrences when the same bug appears twice in one file" do
    two = @two_bugs <> @two_bugs

    confirm_fix(fix(two), @two_bugs_repaired <> @two_bugs_repaired)
    assert valid_syntax?(fix(two))
  end

  # Line numbers are reported against the *input*, not against the intermediate
  # source the second pass sees: copy 2's `)` sits on input line 14, and the
  # first pass has already deleted a line above it.
  test "reports every occurrence it rewrites, at its line in the input" do
    assert [
             %Issue{rule: :close_unclosed_fn_delimiter, meta: %{line: 5}},
             %Issue{rule: :close_unclosed_fn_delimiter, meta: %{line: 14}}
           ] = analyze(@two_bugs <> @two_bugs)
  end

  # Locality: a second, unrelated fault elsewhere in the file must not veto the
  # repair of a genuine occurrence. The occurrence here really is this rule's
  # shape — inserting `end` before the `)` leaves a stray `end` on line 6, and
  # the enclosing `(` the parser names for it is the `Enum.map(` on line 3,
  # above the repair.
  test "repairs its own occurrence on a file that is also broken for an unrelated reason" do
    expected = """
    defmodule Local do
      def go(m) do
        Enum.map(m, fn r ->
          Enum.map(r, fn e ->
            if e == 0 do 1 else e end end)
        end)
      end

      def broken(, do: 1
    end
    """

    confirm_fix(fix(@local_source), expected)
  end

  # The shape this rule promises never to touch (moduledoc: "when inserting `end`
  # before `)` already yields parseable code, that is NoUnclosedFnDelimiter's
  # case"). Inserting `end` on line 4 leaves lines 1-6 perfectly balanced: there
  # is no stray `end` anywhere. The only "`(` closed by `end`" complaint in the
  # file belongs to the unrelated `def broken(` on line 8, *below* the repair —
  # a signal that says nothing about whether line 5 is stray.
  test "declines the plain-unclosed-fn shape even when an unrelated ( is closed by an end below" do
    input = """
    defmodule PlainShape do
      def a(m) do
        Enum.map(m, fn r ->
          if r == 0 do 1 else r end)
        end
      end

      def broken(, do: 1
    end
    """

    confirm_fix(fix(input), input)
    assert analyze(input) == []
  end

  # The reviewer's reduction of the same defect, with no enclosing call at all
  # around the `fn`: after inserting `end` on line 3 the module is balanced, so
  # the rule must stay silent. Deleting `def a`'s own `end` (line 4) on the
  # strength of the unrelated `def broken(` on line 6 destroys the file.
  test "does not delete a real end on the strength of an unrelated ( closed by an end below" do
    input = """
    defmodule Reduced do
      def a(list) do
        Enum.max_by(list, fn {_, s} -> s)
      end

      def broken(, do: 1
    end
    """

    confirm_fix(fix(input), input)
    assert analyze(input) == []
  end

  # The same defect as the two tests above, but with the unrelated `(` *above*
  # the repair instead of below. `def broken(` on line 2 is never closed, so the
  # parser blames the module's own final `end` on it — an identically shaped
  # "`(` closed by `end`" complaint that says nothing about line 5. Reading it as
  # "there is a stray `end` of mine below" deletes `def go`'s own terminator on
  # line 6. This is again the plain unclosed-`fn` shape that belongs to
  # `NoUnclosedFnDelimiter`; there is no stray `end` in this file at all.
  test "does not delete a real end on the strength of an unrelated ( closed by an end above" do
    input = """
    defmodule AboveReduced do
      def broken(, do: 1

      def go(list) do
        Enum.max_by(list, fn {_, s} -> s)
      end
    end
    """

    confirm_fix(fix(input), input)
    assert analyze(input) == []
  end

  # The same shape with a further function below, so that the terminator the
  # rule would delete is unmistakably a real one: `def go`'s `end` on line 6,
  # with `def other` still to come.
  test "does not delete a real end above a later function on the strength of an unrelated ( above" do
    input = """
    defmodule AboveWithTail do
      def broken(, do: 1

      def go(list) do
        Enum.max_by(list, fn {_, s} -> s)
      end

      def other do
        :ok
      end
    end
    """

    confirm_fix(fix(input), input)
    assert analyze(input) == []
  end

  # A genuine occurrence of this rule's own shape (stray `end` on line 8) that
  # sits below an unclosed `(`. The complaint the rule would have to reason from
  # belongs to that broken `(` on line 2, not to the repair, so the rule declines
  # rather than acting on evidence that says nothing about line 8.
  test "declines a genuine occurrence whose only evidence is an unrelated ( above" do
    input = """
    defmodule GenuineBelowBroken do
      def broken(, do: 1

      def go(m) do
        Enum.map(m, fn r ->
          Enum.map(r, fn e ->
            if e == 0 do 1 else e end)
          end
        end)
      end
    end
    """

    confirm_fix(fix(input), input)
    assert analyze(input) == []
  end

  # The stray `end` this rule exists to delete is the first `end` *token* after
  # the `)` it repaired. Here that `end` carries a trailing comment, so deleting
  # its whole line would take the comment with it — the rule must decline. What
  # it must not do is walk past it to the next bare `end` line and delete the
  # `case`'s own terminator, which happens to rebalance the file (the stray
  # `end` then closes the `case`) and so passes every "does it parse" check.
  test "declines rather than deleting a real end when the stray end is not alone on its line" do
    input = """
    defmodule NotAlone do
      def go(m) do
        Enum.map(m, fn r ->
          case r do
            0 ->
              Enum.map(r, fn e ->
                if e == 0 do 1 else e end)
              end # the stray end, with a comment
            _ -> r
          end
        end)
      end
    end
    """

    confirm_fix(fix(input), input)
    assert analyze(input) == []
  end

  # The same bound, where the wrong deletion does *not* rebalance the file: the
  # first `end` token below the repair is the comment-carrying stray on line 6,
  # not the `if` block's own `end` on line 9.
  test "declines rather than deleting a nested block's own end below the stray" do
    input = """
    defmodule NotAloneBlock do
      def go(m) do
        Enum.map(m, fn r ->
          Enum.map(r, fn e ->
            if e == 0 do 1 else e end)
          end # the stray end, with a comment
          if r > 0 do
            :big
          end
        end)
      end
    end
    """

    confirm_fix(fix(input), input)
    assert analyze(input) == []
  end

  # One pass per occurrence, so three copies of the bug are three passes. This
  # says nothing about the bound on that loop — `@max_passes` is 100 — which the
  # two tests after the `Heredoc` one below pin at the boundary itself.
  test "repairs every occurrence when the bug appears three times in one file" do
    one = """
    defmodule ThreeBugs do
      def a(m) do
        Enum.map(m, fn r ->
          Enum.map(r, fn e ->
            if e == 0 do 1 else e end)
          end
        end)
      end
    end
    """

    expected_one = """
    defmodule ThreeBugs do
      def a(m) do
        Enum.map(m, fn r ->
          Enum.map(r, fn e ->
            if e == 0 do 1 else e end end)
        end)
      end
    end
    """

    input = one <> one <> one
    confirm_fix(fix(input), expected_one <> expected_one <> expected_one)
    assert valid_syntax?(fix(input))

    assert [
             %Issue{rule: :close_unclosed_fn_delimiter, meta: %{line: 5}},
             %Issue{rule: :close_unclosed_fn_delimiter, meta: %{line: 14}},
             %Issue{rule: :close_unclosed_fn_delimiter, meta: %{line: 23}}
           ] = analyze(input)
  end

  # The one test that actually reaches the line-delete on a source whose ONLY
  # fault is this bug, and whose first bare `end` line at or below the insertion
  # point is heredoc *content*. The downward scan does not exclude it — it is
  # below the insertion line, so it is considered — and it must survive.
  test "steps over a bare end line that is heredoc content and deletes the real stray end" do
    input = """
    defmodule Heredoc do
      def go(m) do
        Enum.map(m, fn r ->
          Enum.map(r, fn e ->
            if e == 0 do 1 else e end)
          IO.puts(\"\"\"
          end
          \"\"\")
          end
        end)
      end
    end
    """

    expected = """
    defmodule Heredoc do
      def go(m) do
        Enum.map(m, fn r ->
          Enum.map(r, fn e ->
            if e == 0 do 1 else e end end)
          IO.puts(\"\"\"
          end
          \"\"\")
        end)
      end
    end
    """

    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))
  end

  # The bound on the multi-pass loop, at the boundary itself. `@max_passes` is
  # 100 (lib/syntax/close_unclosed_fn_delimiter.ex) and one occurrence costs one
  # pass, so a file with exactly 100 occurrences is the largest the rule repairs
  # in full: the bound does not cut a real file short.
  test "repairs every occurrence of a file that sits exactly on the pass bound" do
    fixed = fix(String.duplicate(@one_occurrence, 100))

    confirm_fix(fixed, String.duplicate(@one_occurrence_repaired, 100))
    assert valid_syntax?(fixed)
    assert length(analyze(String.duplicate(@one_occurrence, 100))) == 100
  end

  # One occurrence past the bound, and the rule stops where the bound stops: the
  # first 100 copies come back repaired, the 101st is handed back exactly as it
  # arrived, and the result does not parse. `analyze/1` reports only the 100 it
  # rewrote — the last at line 398, with nothing for the occurrence at line 402.
  # So an over-long file comes back silently partial rather than declined, and a
  # caller cannot tell that from a full repair by the return value alone. Pinned
  # here so that changing it is a deliberate act rather than a surprise.
  test "stops at the pass bound, returning a partial repair and reporting only what it rewrote" do
    input = String.duplicate(@one_occurrence, 101)
    fixed = fix(input)

    confirm_fix(fixed, String.duplicate(@one_occurrence_repaired, 100) <> @one_occurrence)
    refute valid_syntax?(fixed)

    issues = analyze(input)
    assert length(issues) == 100
    assert %Issue{rule: :close_unclosed_fn_delimiter, meta: %{line: 398}} = List.last(issues)
  end

  test "leaves a later function's own end alone when there is no stray end to delete" do
    input = """
    defmodule NoStray do
      def a(list) do
        Enum.max_by(list, fn {_, second} -> second)
      end

      def b do
        :ok
      end
    end
    """

    confirm_fix(fix(input), input)
    assert analyze(input) == []
  end

  # The limit on "local" that the moduledoc now spells out. Line 3 is a plain
  # unclosed `fn` (`NoUnclosedFnDelimiter`'s shape) and lines 7-11 are a genuine
  # occurrence of *this* rule's shape. The parser's first complaint is line 3's,
  # so this rule inserts `end` there, and the complaint left over is the second
  # occurrence's `fn`/`)` mismatch — not the extra-`end` complaint it needs. It
  # declines the whole file, and the sibling declines too, so neither rule
  # repairs anything on this input.
  test "declines a file whose first fault is the sibling rule's plain unclosed fn" do
    input = """
    defmodule Both do
      def a(list) do
        Enum.max_by(list, fn {_, s} -> s)
      end

      def go(m) do
        Enum.map(m, fn r ->
          Enum.map(r, fn e ->
            if e == 0 do 1 else e end)
          end
        end)
      end
    end
    """

    confirm_fix(fix(input), input)
    assert analyze(input) == []

    confirm_fix(NoUnclosedFnDelimiter.fix(input), input)
    assert NoUnclosedFnDelimiter.analyze(input) == []
  end

  # Fixing twice can only say something about the repair when the once-fixed
  # source *still does not parse*. On output that parses, the second `fix/1`
  # call stops inside `detect/1` at the parser and hands the source straight
  # back, never reaching the insertion or the deletion — the same short-circuit
  # "does not modify already-valid code" already covers. So each of these two
  # tests refutes `valid_syntax?` on the once-fixed source first; that assertion
  # is what stops the fixture from silently degrading into that short-circuit
  # again.
  #
  # Here the leftover fault is a plain unclosed `fn` (the sibling rule's shape),
  # so the second call gets the furthest a second call can: the parser's first
  # complaint is an `fn` closed by `)`, the rule inserts `end` before it, and
  # only then does the "is the leftover `end` a stray one of mine?" guard turn
  # it back. A rule that skipped that guard would delete `def plain`'s own `end`
  # on the second call.
  test "fixing twice changes nothing when the leftover fault is a plain unclosed fn" do
    input = """
    defmodule GenuineThenPlain do
      def go(m) do
        Enum.map(m, fn r ->
          Enum.map(r, fn e ->
            if e == 0 do 1 else e end)
          end
        end)
      end

      def plain(list) do
        Enum.max_by(list, fn {_, s} -> s)
      end
    end
    """

    once = fix(input)
    refute valid_syntax?(once)
    confirm_fix(fix(once), once)
  end

  # The same guarantee where the leftover fault is an unrelated broken call.
  # This runs on the once-fixed `@local_source` — literally the same bytes the
  # repair test above starts from, so the two cannot drift — whose repair
  # correctly leaves `def broken(, do: 1` behind. The second call is turned back
  # one step earlier: the parser's first complaint about this source is that
  # unclosed `(`, not an `fn` closed by `)`. It is still a call the rule has to
  # decline on unparseable input rather than on "it already parses".
  test "fixing twice changes nothing when the leftover fault is an unrelated broken call" do
    once = fix(@local_source)
    refute valid_syntax?(once)
    confirm_fix(fix(once), once)
  end
end
