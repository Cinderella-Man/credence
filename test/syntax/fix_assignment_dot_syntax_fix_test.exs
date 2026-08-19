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
    "x =  .foo()"
  ]

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
      {:docs_v1, _, _, _, %{"en" => doc}, _, _} = Code.fetch_docs(FixAssignmentDotSyntax)
      [_, section] = Regex.run(~r/##\s+Not flagged\n(.*?)(?=\n##\s)/s, doc)

      unlisted = Enum.reject(@declined, &String.contains?(section, &1))

      assert unlisted == [],
             """
             These shapes are declined and pinned as no-ops above, but the
             moduledoc's "Not flagged" list does not name them, so the rule
             reads as having broader coverage than it has:

               #{Enum.join(unlisted, "\n  ")}
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

    # The class is widened byte-wise rather than with the `u` modifier on
    # purpose: a `/u` regex raises ArgumentError on a subject that is not
    # valid UTF-8, and model output truncated mid-character is exactly the
    # input this phase exists to repair. A missed fix is the right failure
    # there; a crash inside the fix pipeline is not.
    test "a line that is not valid UTF-8 is repaired, not crashed on" do
      code = <<"ref =.make_ref() # ", 0xFF>>

      confirm_fix(fix(code), <<"ref = make_ref() # ", 0xFF>>)
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
      code = ~S'''
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

      fixed = fix(code)

      assert fixed =~ "    ref = make_ref()"
      assert fixed =~ "doc =.example()"
      assert valid_syntax?(fixed)
    end

    test "the rule does not rewrite its own source file" do
      source = File.read!("lib/syntax/fix_assignment_dot_syntax.ex")

      confirm_fix(fix(source), source)
    end
  end
end
