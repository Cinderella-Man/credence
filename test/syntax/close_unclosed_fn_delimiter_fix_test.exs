defmodule Credence.Syntax.CloseUnclosedFnDelimiterFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Issue
  alias Credence.Syntax.CloseUnclosedFnDelimiter
  alias Credence.Syntax.NoUnclosedFnDelimiter

  defp analyze(code), do: CloseUnclosedFnDelimiter.analyze(code)
  defp fix(code), do: CloseUnclosedFnDelimiter.fix(code)

  test "inserts missing end before ) and removes stray end on next line" do
    input = """
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

    expected = """
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

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    code = """
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

    assert analyze(fix(code)) == []
  end

  test "fixed output is well-formed (parses)" do
    code = """
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

    assert valid_syntax?(fix(code))
  end

  test "does not modify already-valid code" do
    code = "Enum.map(list, fn x -> x end)"

    confirm_fix(fix(code), code)
  end

  test "leaves a plain unclosed fn untouched (NoUnclosedFnDelimiter owns it)" do
    code = "list |> Enum.max_by(fn {_, second} -> second)"

    confirm_fix(fix(code), code)
  end

  test "leaves the bug shape inside a docstring untouched when the file is broken elsewhere" do
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
  end

  # The repair is local: it must not wait for the whole file to parse. Two copies
  # of this same bug in one file used to be repaired not at all — each candidate
  # deletion for copy 1 still failed to parse because of copy 2, so the rule
  # returned the source byte-identical and reported nothing.
  test "repairs both occurrences when the same bug appears twice in one file" do
    one = """
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

    expected_one = """
    defmodule TwoBugs do
      def a(m) do
        Enum.map(m, fn r ->
          Enum.map(r, fn e ->
            if e == 0 do 1 else e end end)
        end)
      end
    end
    """

    confirm_fix(fix(one <> one), expected_one <> expected_one)
    assert valid_syntax?(fix(one <> one))
  end

  # Line numbers are reported against the *input*, not against the intermediate
  # source the second pass sees: copy 2's `)` sits on input line 14, and the
  # first pass has already deleted a line above it.
  test "reports every occurrence it rewrites, at its line in the input" do
    one = """
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

    assert [
             %Issue{rule: :close_unclosed_fn_delimiter, meta: %{line: 5}},
             %Issue{rule: :close_unclosed_fn_delimiter, meta: %{line: 14}}
           ] = analyze(one <> one)
  end

  # Locality: a second, unrelated fault elsewhere in the file must not veto the
  # repair of a genuine occurrence. The occurrence here really is this rule's
  # shape — inserting `end` before the `)` leaves a stray `end` on line 6, and
  # the enclosing `(` the parser names for it is the `Enum.map(` on line 3,
  # above the repair.
  test "repairs its own occurrence on a file that is also broken for an unrelated reason" do
    input = """
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

    confirm_fix(fix(input), expected)
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

  # The multi-pass loop is bounded now; the bound must not cut a real file
  # short. Three copies of the bug are three passes.
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
             %Issue{meta: %{line: 5}},
             %Issue{meta: %{line: 14}},
             %Issue{meta: %{line: 23}}
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

  test "fixing twice changes nothing the second time" do
    input = """
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

    once = fix(input <> input)
    confirm_fix(fix(once), once)
  end
end
