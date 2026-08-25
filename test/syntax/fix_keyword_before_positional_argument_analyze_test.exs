defmodule Credence.Syntax.FixKeywordBeforePositionalArgumentAnalyzeTest do
  use ExUnit.Case, async: true

  alias Credence.Issue
  alias Credence.Syntax.FixKeywordBeforePositionalArgument

  defp analyze(code), do: FixKeywordBeforePositionalArgument.analyze(code)

  describe "flags keyword args before positional args" do
    test "keyword before empty list" do
      assert [%Issue{rule: :fix_keyword_before_positional_argument}] =
               analyze("Task.Supervisor.start_link(name: __MODULE__, [])")
    end

    test "keyword before positional identifier" do
      assert [%Issue{rule: :fix_keyword_before_positional_argument}] =
               analyze("foo(name: x, arg)")
    end

    test "multiple keywords before positional" do
      assert [%Issue{rule: :fix_keyword_before_positional_argument}] =
               analyze("foo(key1: 1, key2: 2, arg)")
    end

    test "keyword sandwiched between positionals" do
      assert [%Issue{rule: :fix_keyword_before_positional_argument}] =
               analyze("foo(a, name: x, b)")
    end

    test "nested call as the trailing positional" do
      assert [%Issue{rule: :fix_keyword_before_positional_argument}] =
               analyze("foo(name: 1, bar(2))")
    end

    test "unicode identifiers in the argument list" do
      assert [%Issue{rule: :fix_keyword_before_positional_argument}] =
               analyze("foo(a: ärg_ünicode, brg)")
    end

    test "unicode keyword name" do
      assert [%Issue{rule: :fix_keyword_before_positional_argument}] =
               analyze("foo(árg: 1, positional)")
    end

    test "inside defmodule" do
      input = """
      defmodule TaskSupervisor do
        def start_child do
          Task.Supervisor.start_link(name: __MODULE__, [])
        end
      end
      """

      assert [%Issue{rule: :fix_keyword_before_positional_argument, meta: %{line: 3}}] =
               analyze(input)
    end

    test "call spread over several lines" do
      input = """
      foo(
        name: x,
        arg
      )
      """

      assert [%Issue{rule: :fix_keyword_before_positional_argument, meta: %{line: 2}}] =
               analyze(input)
    end
  end

  describe "leaves good code alone" do
    test "keywords after positional (valid)" do
      assert analyze("foo(bar, name: __MODULE__)") == []
    end

    test "only keywords" do
      assert analyze("foo(name: x, age: 30)") == []
    end

    test "no arguments" do
      assert analyze("foo()") == []
    end

    test "single positional argument" do
      assert analyze("foo(bar)") == []
    end

    test "keywords at end of multi-arg call" do
      assert analyze("Task.Supervisor.start_link([], name: __MODULE__)") == []
    end

    test "empty source" do
      assert analyze("") == []
    end

    test "a whole module that parses" do
      input = """
      defmodule TaskSupervisor do
        def start_child do
          Task.Supervisor.start_link([], name: __MODULE__)
        end
      end
      """

      assert analyze(input) == []
    end
  end

  describe "stays silent on parse errors it does not own" do
    # `Code.string_to_quoted/1` reports some errors with an `{opening, hint}`
    # tuple instead of a binary message; the rule must not blow up on those.
    test "stray end (tuple-shaped error message)" do
      input = """
      def f do
        1
      end
      end
      """

      assert analyze(input) == []
    end

    test "missing terminator" do
      input = """
      defmodule M do
        def f do
          :ok
      end
      """

      assert analyze(input) == []
    end

    test "unclosed paren" do
      assert analyze("foo(1, 2") == []
    end
  end

  describe "declines the cases the textual split cannot be trusted on" do
    # Every case below really is keyword-before-positional, and every one is
    # deliberately left alone: a comma (or bracket) can hide inside a string,
    # charlist, comment, sigil, char literal or clause head, so splitting the
    # argument text on top-level commas would silently produce a *different*,
    # parseable program. `foo(a: ",", b)` is the proof: a naive split rewrites
    # it to `foo(", b, a: ")`.
    test "comma inside a string literal" do
      assert analyze(~S'foo(a: ",", b)') == []
    end

    test "string argument without a comma" do
      assert analyze(~S'foo(name: "x", arg)') == []
    end

    test "charlist argument" do
      assert analyze("foo(name: 'x', arg)") == []
    end

    test "comment inside the argument list" do
      input = """
      foo(
        name: x,
        arg
      )
      """

      commented = String.replace(input, "name: x,", "name: x, # why")
      assert analyze(commented) == []
    end

    test "sigil argument" do
      assert analyze("foo(name: ~w(a b), arg)") == []
    end

    test "char literal argument" do
      assert analyze("foo(name: ?,, arg)") == []
    end

    test "clause arrow in the argument list" do
      assert analyze("foo(name: 1, fn x -> x end, arg)") == []
    end
  end
end
