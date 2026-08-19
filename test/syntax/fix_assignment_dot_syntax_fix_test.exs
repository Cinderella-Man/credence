defmodule Credence.Syntax.FixAssignmentDotSyntaxFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixAssignmentDotSyntax

  defp analyze(code), do: FixAssignmentDotSyntax.analyze(code)
  defp fix(code), do: FixAssignmentDotSyntax.fix(code)

  describe "fix/1 — removes the extra dot" do
    test "fixes `ref =.make_ref()` to `ref = make_ref()`" do
      confirm_fix(fix("ref =.make_ref()"), "ref = make_ref()")
    end

    test "fixes with space before dot" do
      confirm_fix(fix("ref = .make_ref()"), "ref = make_ref()")
    end

    test "fixes inside a full module" do
      source = """
      defmodule FixAssignmentDotSyntax do
        @moduledoc "Demonstrates Python-style syntax error: extra dot after = in assignment"

        def make_ref_example do
          ref =.make_ref()
          ref
        end
      end
      """

      expected = """
      defmodule FixAssignmentDotSyntax do
        @moduledoc "Demonstrates Python-style syntax error: extra dot after = in assignment"

        def make_ref_example do
          ref = make_ref()
          ref
        end
      end
      """

      confirm_fix(fix(source), expected)
    end

    test "fixes a qualified call" do
      confirm_fix(fix("x =.Module.fun()"), "x = Module.fun()")
    end

    test "fixes multiple occurrences" do
      source = """
      a =.foo()
      b =.bar()
      """

      expected = """
      a = foo()
      b = bar()
      """

      confirm_fix(fix(source), expected)
    end
  end

  describe "fix/1 — no-ops on valid code" do
    test "valid assignment unchanged" do
      code = "ref = make_ref()"
      confirm_fix(fix(code), code)
    end

    test "comparison unchanged" do
      code = "a == b"
      confirm_fix(fix(code), code)
    end

    test "comment line unchanged" do
      code = "# ref =.make_ref()"
      confirm_fix(fix(code), code)
    end

    test "trailing comment containing the bad shape unchanged" do
      code = "x = 1 # ref =.make_ref()"
      confirm_fix(fix(code), code)
    end
  end

  describe "fix/1 — a digit after the dot is left alone" do
    # Dropping the dot here would change the value (`.05` -> the integer `5`)
    # or produce source that does not parse (`.5e3` -> `5e3`), so the rule
    # never touches a digit. See the analyze test for the matching no-issue
    # cases.
    test "python float literal with a space unchanged" do
      code = "rate = .05"
      confirm_fix(fix(code), code)
    end

    test "python float literal without a space unchanged" do
      code = "x =.5"
      confirm_fix(fix(code), code)
    end

    test "python float literal in scientific notation unchanged" do
      code = "x =.5e3"
      confirm_fix(fix(code), code)
    end

    test "a digit line inside a module body is left untouched" do
      code = """
      defmodule Example do
        def rate do
          r =.05
          r
        end
      end
      """

      confirm_fix(fix(code), code)
    end
  end

  # Everything the pattern declines because it wants a bare identifier at the
  # start of the line and at most one space before the dot. One list drives
  # both the no-op tests and the check that the moduledoc names them, so the
  # rule's documented coverage cannot drift away from its real coverage.
  @declined [
    "{:ok, val} =.foo()",
    "@attr =.foo()",
    "x = y =.foo()",
    "x =  .foo()",
    "a =.foo(b =.bar())"
  ]

  # The `x = y =.foo()` entry above is about an `=` that comes *before* the
  # dot. One after the dot is ordinary code and the line is repaired, so a
  # "Not flagged" list that says only "a second `=` on the line" claims a
  # wider abstention than the rule takes.
  @repaired_despite_later_equals "x =.foo(a = 1)"

  describe "fix/1 — shapes the rule does not handle" do
    test "anonymous call syntax unchanged" do
      code = "f =.(1)"
      confirm_fix(fix(code), code)
    end

    for code <- @declined do
      test "unchanged, and not reported: #{code}" do
        confirm_fix(fix(unquote(code)), unquote(code))
        assert analyze(unquote(code)) == []
      end
    end

    test "the moduledoc's `## Not flagged` list names every one of them" do
      section = Credence.RuleDuplication.moduledoc_section(FixAssignmentDotSyntax, "Not flagged")

      unlisted = Enum.reject(@declined, &String.contains?(section, &1))

      assert unlisted == [],
             """
             These shapes are declined and pinned as no-ops above, but the
             moduledoc's "Not flagged" list does not name them, so the rule
             reads as having broader coverage than it has:

               #{Enum.join(unlisted, "\n  ")}
             """
    end

    # The `a =.foo(b =.bar())` entry is the one decline that is not about the
    # shape of the line's *start*. The pattern is anchored at `^`, so a repair
    # can only ever reach the first `=.` on the line — and the half-repaired
    # line is a dead end: it still does not parse, and it no longer matches the
    # anchored pattern, so `analyze/1` would call it clean and no later pass
    # could find the leftover. Emitting nothing is what keeps the rule honest.
    test "a half-repaired line would be a dead end, so the whole line is declined" do
      source = "a =.foo(b =.bar())"
      half_repaired = "a = foo(b =.bar())"

      refute valid_syntax?(source)
      refute valid_syntax?(half_repaired), "the prefix repair alone does not rescue the line"
      assert analyze(half_repaired) == [], "and nothing would report the leftover afterwards"

      confirm_fix(fix(source), source)
      assert analyze(source) == []
    end

    # The tail is inspected in the mask's shadow, exactly like the match
    # itself, so a `=.` that is only text — inside a string literal or a
    # trailing comment — cannot decline a line the rule can repair.
    test "a `=.` in a literal or a comment does not decline the line" do
      confirm_fix(
        fix(~S'x =.foo("b =.bar()") # c =.d()'),
        ~S'x = foo("b =.bar()") # c =.d()'
      )
    end

    test "a second `=` after the dot does not stop the repair" do
      confirm_fix(fix(@repaired_despite_later_equals), "x = foo(a = 1)")
      assert analyze(@repaired_despite_later_equals) != []
    end

    test "the moduledoc's `## Not flagged` list qualifies its second-`=` entry" do
      section = Credence.RuleDuplication.moduledoc_section(FixAssignmentDotSyntax, "Not flagged")

      assert String.contains?(section, @repaired_despite_later_equals),
             """
             The list names `x = y =.foo()` as declined without saying that
             only an `=` *before* the dot declines. `#{@repaired_despite_later_equals}`
             also has a second `=` on the line and is repaired, so the entry
             has to name it or a maintainer reads a wider abstention than the
             rule takes.
             """
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # UNICODE — Elixir variable names are not ASCII-only
  #
  # `café = make_ref()` is perfectly good Elixir and `café =.make_ref()`
  # is the same syntax error as any other line here, so declining it is a
  # missed repair rather than a safe abstention.
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/1 — a non-ASCII variable name" do
    test "repairs an assignment to a Unicode identifier" do
      confirm_fix(fix("café =.make_ref()"), "café = make_ref()")
    end

    test "repairs one with a non-ASCII byte after the first character" do
      confirm_fix(fix("  größe =.byte_size(x)"), "  größe = byte_size(x)")
    end

    test "the repaired line parses and no longer flags" do
      fixed = fix("café =.make_ref()")

      assert valid_syntax?(fixed)
      assert analyze(fixed) == []
    end

    # The string the rule ACTUALLY emitted, compiled — with the unrepaired
    # line through the same compile as the control, so this cannot pass by
    # compiling anything at all.
    test "the emitted repair compiles, and the line it replaced does not" do
      emitted = fix("café =.make_ref()")

      module = fn line ->
        """
        defmodule FixAssignmentDotSyntaxUnicodeExample do
          def go do
            #{line}
            café
          end
        end
        """
      end

      assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(module.(emitted))

      assert {:error, [%{severity: :error}]} =
               Credence.RuleHelpers.compile_and_capture(module.("café =.make_ref()"))
    end

    # The callee is the same story as the variable name: `def über(x)` is
    # valid Elixir, so `x =.über(y)` is the same syntax error as any other
    # line here. Only a *digit* after the dot is ambiguous (see the moduledoc),
    # and a non-ASCII byte is not a digit.
    test "repairs a call to a Unicode function name" do
      confirm_fix(fix("x =.über(y)"), "x = über(y)")
      assert analyze("x =.über(y)") != []
    end

    # The string the rule ACTUALLY emitted, compiled, with the line it
    # replaced through the same compile as the control.
    test "the emitted repair of a Unicode callee compiles, and its input does not" do
      emitted = fix("x =.über(y)")

      module = fn line ->
        """
        defmodule FixAssignmentDotSyntaxUnicodeCalleeExample do
          def über(y), do: y

          def go(y) do
            #{line}
            x
          end
        end
        """
      end

      assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(module.(emitted))

      assert {:error, [%{severity: :error}]} =
               Credence.RuleHelpers.compile_and_capture(module.("x =.über(y)"))
    end

    # A stray byte inside a *comment* never reaches the pattern: masking blanks
    # a comment byte-for-byte, so the subject the regex sees here is pure
    # ASCII. This test pins that the repair still lands and that the mask
    # itself survives the byte — it says nothing about the pattern's own
    # tolerance of invalid UTF-8. The test below is the one that does.
    test "a stray byte in a comment does not disturb the repair" do
      code = <<"ref =.make_ref() # ", 0xFF>>

      confirm_fix(fix(code), <<"ref = make_ref() # ", 0xFF>>)

      [{_line, shadow}] = Credence.SourceMask.lines(code)
      assert String.valid?(shadow), "the comment byte should have been blanked"
    end

    # The class is widened byte-wise rather than with the `u` modifier on
    # purpose: a `/u` regex raises ArgumentError on a subject that is not
    # valid UTF-8, and model output truncated mid-character is exactly the
    # input this phase exists to repair. A missed fix is the right failure
    # there; a crash inside the fix pipeline is not — `Credence.Syntax` calls
    # `fix/1` with no rescue, so one raise takes down the whole file's repair.
    #
    # A truncated character in *code* position is the only input that reaches
    # the pattern still invalid, so this is the test that would go red if the
    # pattern were ever "tidied" to `/u`. The `refute String.valid?` guard is
    # what stops it quietly becoming vacuous.
    test "a truncated multi-byte character in code is repaired, not crashed on" do
      code = <<"caf", 0xC3, " =.make_ref()">>

      [{_line, shadow}] = Credence.SourceMask.lines(code)
      refute String.valid?(shadow), "the fixture must reach the pattern still invalid"

      confirm_fix(fix(code), <<"caf", 0xC3, " = make_ref()">>)
    end

    # What masking guarantees about a high byte reaching the pattern is only
    # that it did not come from a literal — not that it is part of an
    # identifier. Punctuation sits in code position too, which is the very
    # thing `Credence.SourceMask`'s moduledoc is about, so an em dash after
    # the dot is admitted by the byte-wise class: the line is flagged and the
    # dot is removed, and the result still does not parse. Broken in, broken
    # out — the rewrite neither helps nor harms. Telling a letter from an em
    # dash would need `\p{L}`, i.e. the `/u` modifier the test above rules
    # out, so this pins the trade the byte-wise class makes, not a defect.
    test "a non-identifier character in code position: broken in, broken out" do
      refute valid_syntax?("x =.—dash()")
      assert analyze("x =.—dash()") != []

      confirm_fix(fix("x =.—dash()"), "x = —dash()")
      refute valid_syntax?("x = —dash()"), "the repair cannot rescue this line"
    end
  end

  describe "round-trip" do
    test "fixed output no longer flags" do
      assert analyze(fix("ref =.make_ref()")) == []
    end

    test "fixed output is well-formed (parses)" do
      assert valid_syntax?(fix("ref =.make_ref()"))
    end

    test "full module round-trip" do
      source = """
      defmodule FixAssignmentDotSyntax do
        def make_ref_example do
          ref =.make_ref()
          ref
        end
      end
      """

      fixed = fix(source)
      assert valid_syntax?(fixed)
      assert analyze(fixed) == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # LITERALS — the spurious dot named in documentation is not a dot
  #
  # The moduledoc's "Not flagged" list claimed string literals were safe
  # because the `op=` is never the line's leading token. Inside a heredoc
  # that accident runs out: a documentation line may begin with exactly
  # the shape this rule matches, and both of this rule's own `→`
  # examples did (docs/22 T3.10). The decision now runs against a
  # `Credence.SourceMask` shadow.
  # ═══════════════════════════════════════════════════════════════════

  # A file that both documents the broken form and contains it: the heredoc
  # line must survive untouched while the one in `go/0` is repaired.
  @mixed_source ~S'''
  defmodule Both do
    @moduledoc """
  doc =.example()
    """

    def go do
      ref =.make_ref()
      ref
    end
  end
  '''

  describe "fix/1 — only real code is rewritten" do
    test "leaves an assignment inside a moduledoc heredoc alone" do
      code = ~S'''
      defmodule Documented do
        @moduledoc """
            ref =.make_ref()        →  ref = make_ref()
        """
      end
      '''

      confirm_fix(fix(code), code)
    end

    test "leaves an assignment inside a comment alone" do
      code = "# ref =.make_ref()"

      confirm_fix(fix(code), code)
    end

    test "does not report an assignment that only appears in prose" do
      code = ~S'''
      @moduledoc """
      x =.some_function(a)
      """
      '''

      assert analyze(code) == []
    end

    test "still fixes real code in a file that also documents the broken form" do
      expected = ~S'''
      defmodule Both do
        @moduledoc """
      doc =.example()
        """

        def go do
          ref = make_ref()
          ref
        end
      end
      '''

      fixed = fix(@mixed_source)

      confirm_fix(fixed, expected)
      assert valid_syntax?(fixed)
    end

    # CONTROL for the test above. It used to assert with two `=~` substring
    # checks, which say nothing about the rest of the file: this output has had
    # the function's whole return value replaced and still satisfies both of
    # them, plus the parse check. Whole-string equality is what rejects it.
    test "CONTROL: substring checks admit output that is wrong elsewhere" do
      corrupt = String.replace(fix(@mixed_source), "    ref\n", "    :corrupted\n")

      assert corrupt =~ "    ref = make_ref()"
      assert corrupt =~ "doc =.example()"
      assert valid_syntax?(corrupt)
      refute corrupt == fix(@mixed_source)
    end

    test "the rule does not rewrite its own source file" do
      source = File.read!("lib/syntax/fix_assignment_dot_syntax.ex")

      confirm_fix(fix(source), source)
    end
  end
end
