defmodule Credence.Pattern.NoNegativeStepInStringSliceCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoNegativeStepInStringSlice

  describe "NoNegativeStepInStringSlice check" do
    test "flags String.slice(str, n..-1) with variable start" do
      code = """
      defmodule M do
        def suffix(str, n) do
          String.slice(str, n..-1)
        end
      end
      """

      issues = check(NoNegativeStepInStringSlice, code)
      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_negative_step_in_string_slice
    end

    test "flags String.slice(str, 0..-1) with literal start" do
      code = """
      defmodule M do
        def full(str) do
          String.slice(str, 0..-1)
        end
      end
      """

      assert flagged?(NoNegativeStepInStringSlice, code)
    end

    test "flags String.slice(str, 2..-1) with positive literal start" do
      code = """
      defmodule M do
        def skip_two(str) do
          String.slice(str, 2..-1)
        end
      end
      """

      assert flagged?(NoNegativeStepInStringSlice, code)
    end

    test "leaves String.slice(str, n..-1//1) alone" do
      code = """
      defmodule M do
        def suffix(str, n) do
          String.slice(str, n..-1//1)
        end
      end
      """

      assert clean?(NoNegativeStepInStringSlice, code)
    end

    test "leaves String.slice with non-negative range alone" do
      code = """
      defmodule M do
        def mid(str) do
          String.slice(str, 1..3)
        end
      end
      """

      assert clean?(NoNegativeStepInStringSlice, code)
    end

    test "leaves String.slice with negative step alone" do
      code = """
      defmodule M do
        def rev(str) do
          String.slice(str, -1..-1//-1)
        end
      end
      """

      assert clean?(NoNegativeStepInStringSlice, code)
    end

    test "leaves non-String.slice calls alone" do
      code = """
      defmodule M do
        def range(n) do
          Enum.to_list(n..-1)
        end
      end
      """

      assert clean?(NoNegativeStepInStringSlice, code)
    end

    test "leaves String.slice with variable range alone" do
      code = """
      defmodule M do
        def slice(str, r) do
          String.slice(str, r)
        end
      end
      """

      assert clean?(NoNegativeStepInStringSlice, code)
    end

    test "check and fix agree on what to flag" do
      bad = """
      defmodule M do
        def suffix(str, n) do
          String.slice(str, n..-1)
        end
      end
      """

      good = """
      defmodule M do
        def suffix(str, n) do
          String.slice(str, n..-1//1)
        end
      end
      """

      assert flagged?(NoNegativeStepInStringSlice, bad)
      assert clean?(NoNegativeStepInStringSlice, good)
      assert check(NoNegativeStepInStringSlice, fix(NoNegativeStepInStringSlice, bad)) == []
    end
  end

  # The narrowing the acceptance review required before this rule could land.
  #
  # A range defaults to step -1 only when its first element is greater than its
  # last, so a NEGATIVE literal start is never the deprecated form. Measured on
  # Elixir 1.20.2:
  #
  #     String.slice("abcdefghij", 4..-1)   #=> "efghij", 2 warnings
  #     String.slice("abcdefghij", -6..-1)  #=> "efghij", NO warning
  #
  # Flagging it would be an over-fire: the repair would be a no-op change to code
  # the compiler is content with.
  describe "a negative literal start is not the deprecated form" do
    test "String.slice(s, -6..-1) is clean" do
      assert clean?(NoNegativeStepInStringSlice, """
             defmodule M do
               def last_six(s), do: String.slice(s, -6..-1)
             end
             """)
    end

    test "other negative literal starts are clean too" do
      for start <- ["-1", "-2", "-10"] do
        assert clean?(NoNegativeStepInStringSlice, """
               defmodule M do
                 def f(s), do: String.slice(s, #{start}..-1)
               end
               """),
               "#{start}..-1 ascends and warns about nothing"
      end
    end

    # The controls. Narrowing must not turn the rule off for the forms that ARE
    # deprecated — a non-negative literal, and a variable whose runtime value the
    # AST cannot know.
    test "CONTROL: a non-negative literal start still fires" do
      for start <- ["0", "4", "17"] do
        assert flagged?(NoNegativeStepInStringSlice, """
               defmodule M do
                 def f(s), do: String.slice(s, #{start}..-1)
               end
               """),
               "#{start}..-1 defaults to step -1 and is deprecated"
      end
    end

    test "CONTROL: a non-literal start still fires" do
      assert flagged?(NoNegativeStepInStringSlice, """
             defmodule M do
               def f(s, n), do: String.slice(s, n..-1)
             end
             """)
    end
  end

  # Scope parity: the fix must change code ONLY where the check flags. Two holes
  # were open when this rule was accepted, and both were fix-without-report — the
  # mirror of the report-without-fix shape, and just as invisible.
  #
  #   1. `check/2` matched only `String.slice(str, range)` (two arguments) while
  #      `fix_patches/2` carried an explicit branch for the piped one-argument
  #      form, so `s |> String.slice(2..-1)` was rewritten with check=0.
  #   2. The acceptance narrowing (decline a negative literal start) went into
  #      `bare_neg_one_range?/1`, which only `check/2` called — `fix_patches/2`
  #      re-matched the shape inline, so `String.slice(s, -6..-1)` was rewritten
  #      with check=0 too.
  #
  # Both are gone because both callbacks now route through `slice_range/1` and
  # `bare_neg_one_range?/1`. These tests pin that they cannot diverge again.
  describe "scope parity between check and fix" do
    # Written as LITERAL fixtures, not built by interpolation, so
    # `fixture_scope_parity_test.exs` can see them: its collector gathers string
    # literals adjacent to a verb call, and an interpolated fixture leaves nothing
    # to collect. The loop-built cases below cover the same ground for a human
    # reader; these two are what the gate reads.
    test "the piped form is a literal fixture the meta-gates can collect" do
      assert flagged?(NoNegativeStepInStringSlice, """
             defmodule M do
               def f(s), do: s |> String.slice(2..-1)
             end
             """)

      assert flagged?(NoNegativeStepInStringSlice, """
             defmodule M do
               def f(s, n), do: s |> String.slice(n..-1)
             end
             """)
    end

    test "the piped form is reported, not silently rewritten" do
      for src <- ["s |> String.slice(2..-1)", "s |> String.slice(n..-1)"] do
        wrapped = "defmodule M do\n  def f(s, n), do: #{src}\nend\n"
        assert flagged?(NoNegativeStepInStringSlice, wrapped), "#{src} must be reported"
      end
    end

    test "every shape the fix would change is one the check flags" do
      for src <- [
            "String.slice(s, 2..-1)",
            "String.slice(s, n..-1)",
            "s |> String.slice(2..-1)",
            "s |> String.slice(n..-1)",
            "String.slice(s, -6..-1)",
            "String.slice(s, 2..-1//1)",
            "String.slice(s, 2..5)"
          ] do
        wrapped = "defmodule M do\n  def f(s, n), do: #{src}\nend\n"
        flagged = flagged?(NoNegativeStepInStringSlice, wrapped)
        changed = fix(NoNegativeStepInStringSlice, wrapped) != wrapped

        assert flagged == changed,
               "#{src}: check flagged=#{flagged} but fix changed=#{changed}"
      end
    end
  end
end
