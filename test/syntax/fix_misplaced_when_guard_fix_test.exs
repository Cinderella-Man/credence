defmodule Credence.Syntax.FixMisplacedWhenGuardFixTest do
  use ExUnit.Case, async: true

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixMisplacedWhenGuard

  defp analyze(code), do: FixMisplacedWhenGuard.analyze(code)
  defp fix(code), do: FixMisplacedWhenGuard.fix(code)

  describe "deletes the comma in a clause head" do
    test "the field sample" do
      input = """
      defmodule Positive do
        def positive?(x), when x > 0, do: true
      end
      """

      expected = """
      defmodule Positive do
        def positive?(x) when x > 0, do: true
      end
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
      assert analyze(fix(input)) == []
    end

    test "defp" do
      confirm_fix(
        fix("defp ok?(x), when is_atom(x), do: true"),
        "defp ok?(x) when is_atom(x), do: true"
      )
    end

    # The comma is on the line ABOVE the `when`, so the scan back over whitespace has
    # to cross the newline. A line-local search would leave this file unparseable.
    test "split across lines" do
      input = """
      def f(x),
        when x > 0,
        do: x
      """

      expected = """
      def f(x)
        when x > 0,
        do: x
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "a case clause" do
      input = """
      case x do
        y, when y > 0 -> y
        _ -> 0
      end
      """

      expected = """
      case x do
        y when y > 0 -> y
        _ -> 0
      end
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    # A comment between the clause head and its guard is separator as far as the
    # backward scan is concerned — it runs on the shadow, where the comment is blanked,
    # so it neither hides the real comma nor offers its own. Before that, the scan
    # stopped at the first blanked byte and this repairable file was declined.
    test "with a comment between the head and the guard" do
      input = """
      def f(x), # a note
        when x > 0, do: x
      """

      expected = """
      def f(x) # a note
        when x > 0, do: x
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
      assert analyze(fix(input)) == []
    end

    test "an anonymous function clause" do
      confirm_fix(fix("fn y, when y > 0 -> y end"), "fn y when y > 0 -> y end")
      assert valid_syntax?(fix("fn y, when y > 0 -> y end"))
    end
  end

  describe "deletes the when in a comprehension filter" do
    test "the field sample" do
      input = """
      for {name, price} <- items, when price > 100 do
        name
      end
      """

      expected = """
      for {name, price} <- items, price > 100 do
        name
      end
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
      assert analyze(fix(input)) == []
    end

    # The `)` before the comma does not make this a clause head. The locator tracks
    # bracket depth, so the balanced `f()` is skipped and `for` still wins.
    test "when the generator ends in a call" do
      input = """
      for a <- f(), when a > 1 do
        a
      end
      """

      expected = """
      for a <- f(), a > 1 do
        a
      end
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "a for nested in a def body resolves to the for" do
      input = """
      defmodule Nested do
        def g(l) do
          for a <- l, when a > 1 do
            a
          end
        end
      end
      """

      expected = """
      defmodule Nested do
        def g(l) do
          for a <- l, a > 1 do
            a
          end
        end
      end
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    # A filter may be any expression; a guard may not. So deleting the `when` is not
    # just one of two valid repairs here, it is the more general one — moving the guard
    # into the generator pattern instead is a `CompileError` for this fixture, "cannot
    # invoke remote function Kernel.inspect/1 inside a guard".
    test "a filter expression that would be illegal as a guard" do
      input = """
      for a <- l, when String.length(inspect(a)) > 0 do
        a
      end
      """

      expected = """
      for a <- l, String.length(inspect(a)) > 0 do
        a
      end
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    # `delete_when/2` never swallows the newline: joining the lines is a bigger edit
    # than the defect, and it would shift the line numbers `analyze/1` reports for
    # every later repair. With no space after `when` to take, it takes the one before,
    # so the repair does not leave `l, ` with trailing whitespace.
    test "leaves a newline after the when in place, and no trailing whitespace" do
      input = """
      for a <- l, when
        a > 1 do
        a
      end
      """

      expected = """
      for a <- l,
        a > 1 do
        a
      end
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
      refute fix(input) =~ ~r/ \n/
    end
  end

  # `mask/1` keeps the shadow the same number of BYTES as the source, not the same
  # number of graphemes — a multi-byte character becomes one blank byte per byte. The
  # first version of this rule computed grapheme offsets and indexed the shadow with
  # them, so one `é` earlier in the file drifted the position and the verdict came back
  # `:none`. Inert, not corrupting, which is why only a fixture like this catches it.
  describe "is not defeated by multi-byte characters" do
    for {label, prefix} <- [
          {"an accent in a string", ~s|x = "héllo"\n|},
          {"a flag emoji in a comment", "# 🇵🇱 note\n"},
          {"a ZWJ sequence in a comment", "# 👩‍👩‍👧 family\n"},
          {"an accent in a sigil", ~s|x = ~s(café)\n|}
        ] do
      test label do
        input = unquote(prefix) <> "def f(x), when x > 0, do: x\n"
        expected = unquote(prefix) <> "def f(x) when x > 0, do: x\n"

        confirm_fix(fix(input), expected)
        assert valid_syntax?(fix(input))
        assert analyze(fix(input)) == []
      end
    end

    # The edit is byte-wise on both sides, so the literal it did not touch comes back
    # byte-identical rather than re-encoded.
    test "the untouched multi-byte literal is byte-identical" do
      input = """
      x = "héllo 🇵🇱"
      def f(y), when y > 0, do: y
      """

      assert fix(input) =~ ~s|x = "héllo 🇵🇱"|
      assert byte_size(fix(input)) == byte_size(input) - 1
    end

    # And the line numbers stay right, which is the other thing byte offsets buy.
    test "analyze reports the right line past a multi-byte character" do
      input = """
      # 🇵🇱
      x = "café"
      def f(y), when y > 0, do: y
      """

      assert [issue] = analyze(input)
      assert issue.meta.line == 3
    end
  end

  # The measurement that collapsed the two build-list items into one rule. Separately,
  # `for THEN def` came back `[{FixWhenGuardInForComprehension, :rolled_back}]` with the
  # file byte-identical: the Syntax round calls each `fix/1` exactly once, the parser
  # reports only the first error, and `commit_or_roll_back/4` then discards the whole
  # round. One rule that can apply both repairs converges in a single pass.
  describe "repairs every occurrence, both shapes, in one call" do
    test "two clause heads" do
      input = """
      defmodule Both do
        def a(x), when x > 0, do: 1
        def b(y), when y > 0, do: 2
      end
      """

      expected = """
      defmodule Both do
        def a(x) when x > 0, do: 1
        def b(y) when y > 0, do: 2
      end
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "two filters in one comprehension" do
      confirm_fix(
        fix("for x <- l, when x > 1, when x < 9, do: x"),
        "for x <- l, x > 1, x < 9, do: x"
      )

      assert valid_syntax?(fix("for x <- l, when x > 1, when x < 9, do: x"))
    end

    test "for THEN def — the interleaving that defeated two rules" do
      input = """
      defmodule Mixed do
        def g(l) do
          for a <- l, when a > 1, do: a
        end

        def h(x), when x > 0, do: x
      end
      """

      expected = """
      defmodule Mixed do
        def g(l) do
          for a <- l, a > 1, do: a
        end

        def h(x) when x > 0, do: x
      end
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
      assert analyze(fix(input)) == []
    end

    test "def THEN for" do
      input = """
      defmodule Mixed do
        def h(x), when x > 0, do: x

        def g(l) do
          for a <- l, when a > 1, do: a
        end
      end
      """

      expected = """
      defmodule Mixed do
        def h(x) when x > 0, do: x

        def g(l) do
          for a <- l, a > 1, do: a
        end
      end
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    # `analyze/1` and `fix/1` share one loop, so the issue count is the repair count
    # rather than an independent guess at it — and each issue carries the line it was
    # repaired on, which only holds because no edit removes a newline.
    test "analyze reports one issue per repair, with the right line and kind" do
      input = """
      defmodule Mixed do
        def g(l) do
          for a <- l, when a > 1, do: a
        end

        def h(x), when x > 0, do: x
      end
      """

      issues = analyze(input)

      assert length(issues) == 2
      assert Enum.map(issues, & &1.meta.line) == [3, 6]
      assert Enum.any?(issues, &(&1.message =~ "comprehension filter"))
      assert Enum.any?(issues, &(&1.message =~ "Remove the comma"))
    end
  end

  # Both interleavings have to survive the ROUND, not just `fix/1`. This is the
  # assertion whose absence let `NoAtomAsFunctionName` ship inert: every unit test
  # passed while the round rolled the work back.
  describe "the whole round commits instead of rolling back" do
    for {label, code} <- [
          {"for THEN def",
           """
           defmodule Mixed do
             def g(l) do
               for a <- l, when a > 1, do: a
             end

             def h(x), when x > 0, do: x
           end
           """},
          {"def THEN for",
           """
           defmodule Mixed do
             def h(x), when x > 0, do: x

             def g(l) do
               for a <- l, when a > 1, do: a
             end
           end
           """}
        ] do
      test label do
        input = unquote(code)
        {code, applied} = Credence.Syntax.fix_with_trace(input)

        assert applied == [{Credence.Syntax.FixMisplacedWhenGuard, 1}]
        assert valid_syntax?(code)
        refute code == input
      end
    end
  end

  describe "declines, byte for byte" do
    test "source that parses" do
      input = "def f(x) when x > 0, do: x"
      confirm_fix(fix(input), input)
    end

    # A `when` in a generator PATTERN is valid Elixir — the shape this defect is
    # most easily confused with.
    test "a valid when in a generator pattern" do
      input = "for {a, b} when b > 1 <- list, do: a"
      confirm_fix(fix(input), input)
    end

    # Neither repair preserves intent. Deleting the comma does not compile; deleting
    # the `when` compiles and silently stops the guard filtering, because a bare
    # `with` clause is evaluated for effect and its value discarded. Executed:
    #
    #     with {:ok, x} <- {:ok, -5}, x > 0 do {:passed, x} else o -> {:else, o} end
    #     #=> {:passed, -5}
    test "a with clause" do
      input = """
      with {:ok, x} <- f(), when x > 0 do
        x
      end
      """

      confirm_fix(fix(input), input)
    end

    test "a when inside a string, with an unrelated parse error elsewhere" do
      input = """
      x = \"a when b\"
      y = (
      """

      confirm_fix(fix(input), input)
    end

    test "a when inside a comment, with an unrelated parse error elsewhere" do
      input = """
      # guard with when here
      y = (
      """

      confirm_fix(fix(input), input)
    end

    test "an unrelated syntax error" do
      input = "x = foo((1"
      confirm_fix(fix(input), input)
    end
  end

  # A rule keyed on a parse ERROR cannot touch a file that parses, and every source
  # file in the tree parses — so the byte-scope class the self-corruption oracle
  # exists to catch is structurally unreachable here.
  describe "cannot corrupt source that parses" do
    test "its own source, and the locator's, are untouched" do
      for path <- ["lib/syntax/fix_misplaced_when_guard.ex", "lib/syntax/when_guard_position.ex"] do
        own = File.read!(path)

        confirm_fix(fix(own), own)
        assert analyze(own) == []
      end
    end
  end
end
