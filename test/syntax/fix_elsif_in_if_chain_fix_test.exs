defmodule Credence.Syntax.FixElsifInIfChainFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixElsifInIfChain

  defp analyze(code), do: FixElsifInIfChain.analyze(code)
  defp fix(code), do: FixElsifInIfChain.fix(code)

  test "fixes the syntax error" do
    input = ~S"""
    defmodule FixElsifInIfChain do
      def check(data, now) do
        if data.valid_from && DateTime.compare(now, data.valid_from) == :lt do
          {:error, :not_yet_valid}
        elsif data.valid_until && DateTime.compare(now, data.valid_until) == :gt do
          {:error, :expired}
        else
          :ok
        end
      end
    end
    """

    expected = ~S"""
    defmodule FixElsifInIfChain do
      def check(data, now) do
        cond do
          data.valid_from && DateTime.compare(now, data.valid_from) == :lt -> {:error, :not_yet_valid}
          data.valid_until && DateTime.compare(now, data.valid_until) == :gt -> {:error, :expired}
          true -> :ok
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = ~S"""
    defmodule FixElsifInIfChain do
      def check(data, now) do
        if data.valid_from && DateTime.compare(now, data.valid_from) == :lt do
          {:error, :not_yet_valid}
        elsif data.valid_until && DateTime.compare(now, data.valid_until) == :gt do
          {:error, :expired}
        else
          :ok
        end
      end
    end
    """

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule FixElsifInIfChain do
      def check(data, now) do
        if data.valid_from && DateTime.compare(now, data.valid_from) == :lt do
          {:error, :not_yet_valid}
        elsif data.valid_until && DateTime.compare(now, data.valid_until) == :gt do
          {:error, :expired}
        else
          :ok
        end
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  # A branch body of several expressions keeps them as a block under the clause,
  # in order — `cond` evaluates it exactly as the `if` branch did.
  test "keeps a multi-expression branch body as a block" do
    input = ~S"""
    defmodule M do
      def f(n) do
        if n == 0 do
          x = 1
          x + 1
        elsif n > 0 do
          :pos
        else
          :neg
        end
      end
    end
    """

    expected = ~S"""
    defmodule M do
      def f(n) do
        cond do
          n == 0 ->
            x = 1
            x + 1
          n > 0 -> :pos
          true -> :neg
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "multi-expression branch fix is well-formed (parses)" do
    input = ~S"""
    defmodule M do
      def f(n) do
        if n == 0 do
          x = 1
          x + 1
        elsif n > 0 do
          :pos
        else
          :neg
        end
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  # An `if` without an `else` evaluates to `nil` when no branch matches, but a
  # `cond` with no `true` clause raises `CondClauseError`. The fix appends
  # `true -> nil` so the rewrite keeps the original `nil` answer.
  test "no trailing else: appends true -> nil to preserve the nil result" do
    input = ~S"""
    if a do
      1
    elsif b do
      2
    end
    """

    expected = ~S"""
    cond do
      a -> 1
      b -> 2
      true -> nil
    end
    """

    confirm_fix(fix(input), expected)
  end

  # Same story one level down: an empty branch body is `nil` in `if`, and a
  # bodyless `cond` clause does not even parse, so the `nil` is spelled out.
  test "empty branch bodies become explicit nil clauses" do
    input = ~S"""
    if a do
    elsif b do
    else
    end
    """

    expected = ~S"""
    cond do
      a -> nil
      b -> nil
      true -> nil
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "empty-body fix is well-formed (parses)" do
    input = ~S"""
    if a do
    elsif b do
    else
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "keeps a comment-only branch body above an explicit nil" do
    input = ~S"""
    if a do
      # nothing to do
    elsif b do
      2
    else
      3
    end
    """

    expected = ~S"""
    cond do
      a ->
        # nothing to do
        nil
      b -> 2
      true -> 3
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "comment-only branch fix is well-formed (parses)" do
    input = ~S"""
    if a do
      # nothing to do
    elsif b do
      2
    else
      3
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "leaves the code around the chain untouched" do
    input = ~S"""
    before()

    if a do
      1
    elsif b do
      2
    else
      3
    end

    after_it()
    """

    expected = ~S"""
    before()

    cond do
      a -> 1
      b -> 2
      true -> 3
    end

    after_it()
    """

    confirm_fix(fix(input), expected)
  end

  # Everything below is a shape the fix refuses (see the rule's moduledoc): the
  # source comes back byte-identical, and `analyze/1` stays quiet about it.

  test "leaves a multi-line if condition untouched (cannot extract cleanly)" do
    code = ~S"""
    if a and
         b do
      1
    elsif c do
      2
    else
      3
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves a multi-line elsif condition untouched" do
    code = ~S"""
    if a do
      1
    elsif b and
         c do
      2
    else
      3
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves a one-liner elsif (`, do:`) untouched" do
    code = ~S"""
    if a do
      1
    elsif b, do: 2
    else
      3
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves an else with a trailing comment untouched" do
    code = ~S"""
    if a do
      1
    elsif b do
      2
    else # note
      3
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves an if header that is not at the start of its line untouched" do
    code = ~S"""
    r = if a do
      1
    elsif b do
      2
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves a chain with no terminating end untouched" do
    code = ~S"""
    def f(a, b) do
      if a do
        1
      elsif b do
        2
    end
    """

    confirm_fix(fix(code), code)
  end

  # Re-indenting a body line that lives inside a multi-line string literal would
  # change the string's *value*, so those chains are refused outright.
  test "leaves a branch body holding a heredoc untouched" do
    code = """
    if a do
      x = \"""
        content
      \"""
      x
    elsif b do
      2
    else
      3
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves a branch body holding a string spanning lines untouched" do
    code = ~S"""
    if a do
      x = "hello
    world"
      x
    elsif b do
      2
    else
      3
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves an elsif that is documentation inside a heredoc untouched" do
    code = """
    defmodule M do
      @moduledoc \"""
      Bad:

          if a do
            1
          elsif b do
            2
          end
      \"""
      def f, do: :ok
    end

    x =
    """

    confirm_fix(fix(code), code)
  end

  # ═══════════════════════════════════════════════════════════════════
  # `elif` — the Python spelling
  #
  # The moduledoc advertised Python support from the start, but both
  # regexes matched `elsif` only, so `elif` was reported by nothing and
  # repaired by nothing.
  # ═══════════════════════════════════════════════════════════════════

  describe "elif (Python spelling)" do
    test "rewrites an elif chain to cond" do
      code = """
      defmodule Grade do
        def letter(score) do
          if score >= 90 do
            :a
          elif score >= 80 do
            :b
          else
            :c
          end
        end
      end
      """

      expected = """
      defmodule Grade do
        def letter(score) do
          cond do
            score >= 90 -> :a
            score >= 80 -> :b
            true -> :c
          end
        end
      end
      """

      confirm_fix(fix(code), expected)
      assert valid_syntax?(fix(code))
    end

    test "reports an elif chain" do
      code = """
      if a do
        1
      elif b do
        2
      else
        3
      end
      """

      assert [issue] = analyze(code)
      assert issue.rule == :fix_elsif_in_if_chain
      assert issue.message =~ "elif"
    end

    test "elsif and elif produce the same output" do
      elif_code = """
      if a do
        1
      elif b do
        2
      else
        3
      end
      """

      elsif_code = String.replace(elif_code, "elif ", "elsif ")

      confirm_fix(fix(elif_code), fix(elsif_code))
    end

    test "does not touch `else if`, which is valid Elixir" do
      code = """
      if a do
        1
      else
        if b do
          2
        else
          3
        end
      end
      """

      confirm_fix(fix(code), code)
      assert analyze(code) == []
    end
  end
end
