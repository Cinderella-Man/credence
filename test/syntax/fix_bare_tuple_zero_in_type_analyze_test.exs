defmodule Credence.Syntax.FixBareTupleZeroInTypeAnalyzeTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Issue
  alias Credence.Syntax.FixBareTupleZeroInType

  # A `'''` cannot be written literally inside a `"""` heredoc, so this fixture
  # is joined from its lines. The `'''` in the prose is the whole point: it is
  # an ordinary sentence about charlist heredocs, and the rule used to treat it
  # as a delimiter and decide the rest of the file was code.
  @charlist_prose Enum.join(
                    [
                      "defmodule M do",
                      "  @moduledoc \"\"\"",
                      "  Charlist heredocs open with " <> String.duplicate("'", 3) <> ".",
                      "",
                      "  @type t :: () -> any()",
                      "  \"\"\"",
                      "end",
                      ""
                    ],
                    "\n"
                  )

  # The mirror image: a line of real code carrying a lone `"""` inside a sigil.
  # The old delimiter count read it as opening a heredoc, so everything after
  # it was treated as prose and the rule went silent for the rest of the file.
  @triple_quote_in_code Enum.join(
                          [
                            "defmodule M do",
                            "  def q(x), do: String.replace(x, ~s(\"\"\"), \"\")",
                            "  @type t :: () -> any()",
                            "end",
                            ""
                          ],
                          "\n"
                        )

  defp analyze(code), do: FixBareTupleZeroInType.analyze(code)

  describe "analyze/1 — flags a wrappable bare `() ->`" do
    test "flags a bare () before -> in @type" do
      code = """
      defmodule M do
        @moduledoc "types"
        @type task_func :: () -> any()
      end
      """

      # The Syntax phase only runs on source that does not parse, so the rule's
      # own target has to be genuinely unparseable.
      refute valid_syntax?(code)

      assert [%Issue{rule: :fix_bare_tuple_zero_in_type, meta: %{line: 3}}] = analyze(code)
    end

    test "flags a union return type" do
      code = """
      defmodule M do
        @moduledoc "types"
        @type handler :: () -> {:ok, term()} | {:error, term()}
      end
      """

      refute valid_syntax?(code)
      assert [%Issue{rule: :fix_bare_tuple_zero_in_type, meta: %{line: 3}}] = analyze(code)
    end

    test "flags @spec, @callback, @opaque, @typep and @macrocallback alike" do
      code = """
      @spec run() :: () -> any()
      @callback run() :: () -> any()
      @opaque t :: () -> any()
      @typep p :: () -> any()
      @macrocallback m() :: () -> any()
      """

      assert [
               %Issue{meta: %{line: 1}},
               %Issue{meta: %{line: 2}},
               %Issue{meta: %{line: 3}},
               %Issue{meta: %{line: 4}},
               %Issue{meta: %{line: 5}}
             ] = analyze(code)
    end

    test "flags a named spec argument, whose inner `::` is not the separator" do
      assert [%Issue{meta: %{line: 1}}] = analyze("@spec f(t :: integer()) :: () -> any()")
    end

    test "carries a message naming the fix" do
      [issue] = analyze("@type t :: () -> any()")

      assert issue.message ==
               "Bare `()` before `->` in a typespec is ambiguous and fails to parse. " <>
                 "Wrap the function type in parens: `(() -> ...)`."
    end

    test "keeps flagging after a code line that carries a lone triple quote" do
      assert [%Issue{rule: :fix_bare_tuple_zero_in_type, meta: %{line: 3}}] =
               analyze(@triple_quote_in_code)
    end
  end

  describe "analyze/1 — no issue on code that is already right" do
    test "already-parenthesized (() -> ...)" do
      code = """
      defmodule M do
        @type task_func :: (() -> any())
      end
      """

      assert analyze(code) == []
    end

    test "a parenthesized function type inside a union" do
      assert analyze("@type t :: (() -> any()) | (() -> nil)") == []
    end

    test "a parenthesized function type nested in a tuple" do
      assert analyze("@type t :: {(() -> any()), integer()}") == []
    end

    test "non-function types" do
      code = """
      defmodule M do
        @type name :: atom()
        @type count :: integer()
      end
      """

      assert analyze(code) == []
    end

    test "an arity-one function type, which parses on its own" do
      assert analyze("@type t :: (integer() -> boolean())") == []
    end
  end

  describe "analyze/1 — shapes the rule deliberately skips" do
    # Each of these carries the bad `:: () ->` text, but appending `)` at end
    # of line would produce source that still does not parse (or would corrupt
    # unrelated text), so the rule stays quiet rather than flag what its fix
    # cannot repair. The fix test pins the matching no-ops.
    test "a trailing comment" do
      assert analyze("@type t :: () -> any() # zero-arity callback") == []
    end

    test "a whole-line comment" do
      assert analyze("# @type task_func :: () -> any()") == []
    end

    test "nothing after the arrow" do
      assert analyze("@type t :: () ->") == []
    end

    test "a trailing comma" do
      assert analyze("@type t :: () -> any(),") == []
    end

    test "a trailing pipe" do
      assert analyze("@type t :: () -> any() |") == []
    end

    test "an unbalanced tail — the arrow type is a spec argument" do
      assert analyze("@spec f(x :: () -> any()) :: :ok") == []
    end

    test "a `when` guard, which belongs outside the wrap" do
      assert analyze("@spec f(a) :: () -> any() when a: var") == []
    end

    test "a second top-level arrow, which one wrap cannot repair" do
      assert analyze("@type t :: () -> any() -> nil") == []
    end

    test "a string literal on the line" do
      assert analyze(~S'@typedoc "see @type t :: () -> any()"') == []
    end

    test "a line that is not a typespec attribute" do
      assert analyze("x = :: () -> 1") == []
    end

    test "a typespec example inside a doc heredoc" do
      code = ~S'''
      defmodule M do
        @moduledoc """
        @type t :: () -> any()
        """
      end
      '''

      assert analyze(code) == []
    end

    test "a typespec example inside a doc heredoc whose prose mentions a charlist heredoc" do
      assert analyze(@charlist_prose) == []
    end

    test "a type that continues onto the next line" do
      code = """
      @type t :: () -> {:ok, term()}
        | {:error, term()}
      """

      assert analyze(code) == []
    end

    test "a type that continues after a blank line" do
      code = """
      @type t :: () -> {:ok, term()}

        | {:error, term()}
      """

      assert analyze(code) == []
    end

    test "a `when` guard on the line below" do
      code = """
      @spec f(a) :: () -> any()
            when a: var
      """

      assert analyze(code) == []
    end

    test "a range return type that continues onto the next line" do
      code = """
      @type t :: () -> 1
        .. 10
      """

      assert analyze(code) == []
    end

    test "a tail with mismatched bracket kinds" do
      assert analyze("@type t :: () -> [integer()}") == []
    end

    test "a stray closing bracket before the separator" do
      assert analyze("@type t) :: () -> any()") == []
    end

    test "a `::` split across lines" do
      code = """
      @type t ::
        () -> any()
      """

      assert analyze(code) == []
    end
  end
end
