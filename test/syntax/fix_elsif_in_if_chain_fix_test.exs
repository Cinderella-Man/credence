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

    # Renamed for accuracy when the rule was widened to also match same-line
    # `else if` (docs/22 T3.10a). What is untouched here is `else` and `if` on
    # SEPARATE lines with the nested `if` properly closed — a shape the
    # line-based `@elsif_re` cannot match at all, and valid Elixir besides.
    test "does not touch a properly nested `else` + `if` on separate lines" do
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

  # ═══════════════════════════════════════════════════════════════════
  # `else if` — the third spelling, and the terminator count
  #
  # docs/22 T3.10a. `Credence.Syntax.NoElseIf` was this rule's
  # pre-hardening twin — same failure mode, different spelling, one
  # hardened implementation — and was **retired into this rule** once
  # these tests were green. That makes this block the surviving record
  # of everything it could do: its seven scenarios, followed by the four
  # shapes it got wrong. Do not thin it out; deleting a rule is only safe
  # while its behaviour is pinned somewhere, and this is the somewhere.
  #
  # The spellings are NOT interchangeable. `elsif`/`elif` are not Elixir,
  # so every occurrence is the mistake. `else if` is legal — `else` plus a
  # nested `if` opening its own block — so a chain of N headers is the
  # broken Python transplant with ONE terminator and valid code with N+1.
  # The count is the entire difference, which is why it is checked only
  # for this spelling.
  # ═══════════════════════════════════════════════════════════════════

  describe "else if (Python transplant) — the scenarios inherited from NoElseIf" do
    test "rewrites a basic else-if chain to cond" do
      input = """
      if n == 0 do
        list
      else if n >= length(list) do
        []
      else
        List.take(list, length(list) - n)
      end
      """

      expected = """
      cond do
        n == 0 -> list
        n >= length(list) -> []
        true -> List.take(list, length(list) - n)
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "the rewrite parses and no longer flags" do
      input = """
      if n == 0 do
        list
      else if n >= length(list) do
        []
      else
        List.take(list, length(list) - n)
      end
      """

      assert valid_syntax?(fix(input))
      assert analyze(fix(input)) == []
    end

    test "a comment-only else body keeps the comment and supplies nil" do
      input = """
      if n == 0 do
        [1]
      else if n == 1 do
        [1, 1]
      else
        # comment only, no expression
      end
      """

      expected = """
      cond do
        n == 0 -> [1]
        n == 1 -> [1, 1]
        true ->
          # comment only, no expression
          nil
      end
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "no trailing else: appends true -> nil to preserve the nil result" do
      input = """
      if a do
        p
      else if b do
        q
      end
      """

      expected = """
      cond do
        a -> p
        b -> q
        true -> nil
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "leaves a multi-line if condition untouched" do
      input = """
      if a and
           b do
        list
      else if c do
        []
      else
        other
      end
      """

      confirm_fix(fix(input), input)
      assert analyze(input) == []
    end

    test "leaves a multi-line else-if condition untouched" do
      input = """
      if a do
        p
      else if b and
           c do
        q
      else
        r
      end
      """

      confirm_fix(fix(input), input)
    end

    test "leaves an if line with a trailing comment after do untouched" do
      input = """
      if a do # note
        p
      else if b do
        q
      else
        r
      end
      """

      confirm_fix(fix(input), input)
    end

    test "leaves a one-liner else-if (`, do:`) untouched" do
      input = """
      if a do
        p
      else if b, do: q
      else
        r
      end
      """

      confirm_fix(fix(input), input)
    end
  end

  describe "else if — the four modes the retired NoElseIf got wrong" do
    # THE one that matters: this source PARSES. `else if` is `else` plus a
    # nested `if` that closes itself, so both terminators are real and the
    # code means what it says. Rewriting it emits a `cond` plus a stray
    # `end` — output that does not parse, produced from input that did.
    test "declines a valid nested if — two terminators, not one" do
      code = """
      if a do
        1
      else if b do
        2
      else
        3
      end
      end
      """

      assert valid_syntax?(code), "the premise of this test is that the input is VALID Elixir"

      confirm_fix(fix(code), code)
      assert analyze(code) == []
    end

    test "declines a chain with no terminator at all" do
      # Without an `end` there is nothing to bound the rewrite, so a
      # line-based fix swallows the rest of the file.
      code = """
      if a do
        1
      else if b do
        2
      """

      confirm_fix(fix(code), code)
      assert analyze(code) == []
    end

    test "declines `else # note` rather than folding the body into the previous branch" do
      code = """
      if a do
        1
      else if b do
        2
      else # note
        3
      end
      """

      confirm_fix(fix(code), code)
      assert analyze(code) == []
    end

    test "an empty branch body becomes an explicit nil, not a bodyless clause" do
      code = """
      if a do
      else if b do
        2
      else
        3
      end
      """

      expected = """
      cond do
        a -> nil
        b -> 2
        true -> 3
      end
      """

      confirm_fix(fix(code), expected)
      assert valid_syntax?(fix(code))
    end
  end
end
