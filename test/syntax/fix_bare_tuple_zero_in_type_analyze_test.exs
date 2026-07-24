defmodule Credence.Syntax.FixBareTupleZeroInTypeAnalyzeTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Issue
  alias Credence.Syntax.FixBareTupleZeroInType

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
      assert issue.message =~ "Wrap the function type in parens"
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
