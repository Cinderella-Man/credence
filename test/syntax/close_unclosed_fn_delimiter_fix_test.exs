defmodule Credence.Syntax.CloseUnclosedFnDelimiterFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Issue
  alias Credence.Syntax.CloseUnclosedFnDelimiter

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

  test "repairs its own occurrence on a file that is also broken for an unrelated reason" do
    input = """
    defmodule Mixed do
      def a(m) do
        Enum.map(m, fn r ->
          if r == 0 do 1 else r end)
        end
      end

      def broken(, do: 1
    end
    """

    expected = """
    defmodule Mixed do
      def a(m) do
        Enum.map(m, fn r ->
          if r == 0 do 1 else r end end)
      end

      def broken(, do: 1
    end
    """

    confirm_fix(fix(input), expected)
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
