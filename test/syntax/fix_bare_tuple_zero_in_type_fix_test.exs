defmodule Credence.Syntax.FixBareTupleZeroInTypeFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixBareTupleZeroInType

  defp analyze(code), do: FixBareTupleZeroInType.analyze(code)
  defp fix(code), do: FixBareTupleZeroInType.fix(code)

  describe "fix/1 — wraps the function type" do
    test "wraps a bare () in a @type declaration" do
      input = """
      defmodule M do
        @moduledoc "types"
        @type task_func :: () -> any()
      end
      """

      expected = """
      defmodule M do
        @moduledoc "types"
        @type task_func :: (() -> any())
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "wraps a union return type" do
      input = """
      defmodule M do
        @moduledoc "types"
        @type handler :: () -> {:ok, term()} | {:error, term()}
      end
      """

      expected = """
      defmodule M do
        @moduledoc "types"
        @type handler :: (() -> {:ok, term()} | {:error, term()})
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "wraps a nested function type in the return position" do
      confirm_fix(
        fix("@type t :: () -> (integer() -> boolean())"),
        "@type t :: (() -> (integer() -> boolean()))"
      )
    end

    test "wraps every typespec attribute form" do
      input = """
      @spec run() :: () -> any()
      @callback run() :: () -> any()
      @opaque t :: () -> any()
      @typep p :: () -> any()
      @macrocallback m() :: () -> any()
      """

      expected = """
      @spec run() :: (() -> any())
      @callback run() :: (() -> any())
      @opaque t :: (() -> any())
      @typep p :: (() -> any())
      @macrocallback m() :: (() -> any())
      """

      confirm_fix(fix(input), expected)
    end

    test "wraps at the top-level `::`, not at a named argument's `::`" do
      confirm_fix(
        fix("@spec f(t :: integer()) :: () -> any()"),
        "@spec f(t :: integer()) :: (() -> any())"
      )
    end

    test "keeps the indentation and the spacing before the separator" do
      confirm_fix(fix("    @type t   :: ()->any()"), "    @type t   :: (()->any())")
    end

    test "keeps the line's trailing whitespace, including a CRLF carriage return" do
      confirm_fix(fix("@type t :: () -> any()\r"), "@type t :: (() -> any())\r")
      confirm_fix(fix("@type t :: () -> any()  "), "@type t :: (() -> any())  ")
    end
  end

  describe "fix/1 — no-ops on code that is already right" do
    test "already-parenthesized (() -> ...)" do
      code = """
      defmodule M do
        @type task_func :: (() -> any())
      end
      """

      confirm_fix(fix(code), code)
    end

    test "a parenthesized function type inside a union" do
      code = "@type t :: (() -> any()) | (() -> nil)"
      confirm_fix(fix(code), code)
    end

    test "a parenthesized function type nested in a tuple" do
      code = "@type t :: {(() -> any()), integer()}"
      confirm_fix(fix(code), code)
    end

    test "non-function types" do
      code = """
      defmodule M do
        @type name :: atom()
        @type count :: integer()
      end
      """

      confirm_fix(fix(code), code)
    end
  end

  describe "fix/1 — leaves the skipped shapes byte-identical" do
    # The matching "no issue" cases live in the analyze test: check and fix
    # agree that none of these is repairable by appending a `)`.
    test "a trailing comment" do
      code = "@type t :: () -> any() # zero-arity callback"
      confirm_fix(fix(code), code)
    end

    test "a whole-line comment" do
      code = "# @type task_func :: () -> any()"
      confirm_fix(fix(code), code)
    end

    test "nothing after the arrow" do
      code = "@type t :: () ->"
      confirm_fix(fix(code), code)
    end

    test "a trailing comma" do
      code = "@type t :: () -> any(),"
      confirm_fix(fix(code), code)
    end

    test "a trailing pipe" do
      code = "@type t :: () -> any() |"
      confirm_fix(fix(code), code)
    end

    test "an unbalanced tail — the arrow type is a spec argument" do
      code = "@spec f(x :: () -> any()) :: :ok"
      confirm_fix(fix(code), code)
    end

    test "a `when` guard, which belongs outside the wrap" do
      code = "@spec f(a) :: () -> any() when a: var"
      confirm_fix(fix(code), code)
    end

    test "a second top-level arrow, which one wrap cannot repair" do
      code = "@type t :: () -> any() -> nil"
      confirm_fix(fix(code), code)
    end

    test "a string literal on the line" do
      code = ~S'@typedoc "see @type t :: () -> any()"'
      confirm_fix(fix(code), code)
    end

    test "a line that is not a typespec attribute" do
      code = "x = :: () -> 1"
      confirm_fix(fix(code), code)
    end

    test "a stray closing bracket before the separator" do
      code = "@type t) :: () -> any()"
      confirm_fix(fix(code), code)
    end

    test "a `::` split across lines" do
      code = """
      @type t ::
        () -> any()
      """

      confirm_fix(fix(code), code)
    end

    test "a typespec example inside a doc heredoc" do
      code = ~S'''
      defmodule M do
        @moduledoc """
        @type t :: () -> any()
        """
      end
      '''

      confirm_fix(fix(code), code)
    end

    test "code after a heredoc closes is still fixed" do
      input = ~S'''
      defmodule M do
        @moduledoc """
        @type t :: () -> any()
        """
        @type t :: () -> any()
      end
      '''

      expected = ~S'''
      defmodule M do
        @moduledoc """
        @type t :: () -> any()
        """
        @type t :: (() -> any())
      end
      '''

      confirm_fix(fix(input), expected)
    end
  end

  describe "round-trip — the output parses and no longer flags" do
    test "module with a bad @type" do
      code = """
      defmodule M do
        @moduledoc "types"
        @type task_func :: () -> any()

        def run(f), do: f.()
      end
      """

      refute valid_syntax?(code)

      expected = """
      defmodule M do
        @moduledoc "types"
        @type task_func :: (() -> any())

        def run(f), do: f.()
      end
      """

      confirm_fix(fix(code), expected)
      assert valid_syntax?(fix(code))
      assert analyze(fix(code)) == []
    end

    test "across generated lines, a line is flagged exactly when it is rewritten, and every rewrite parses" do
      attrs = ["@type t", "@typep t", "@opaque t", "@spec f()", "@callback f(x)", "@typedoc", "def f"]
      separators = [" :: ", "::", "  ::  "]

      right_hand_sides = [
        "() -> any()",
        "()->any()",
        "() -> {:ok, term()} | {:error, term()}",
        "() -> (integer() -> boolean())",
        "() -> %{a: [integer()]}",
        "() ->",
        "() -> any(),",
        "() -> any() |",
        "() -> any() -> nil",
        "() -> any() when a: var",
        "(() -> any())",
        "integer()"
      ]

      suffixes = ["", " ", "\r", " # note"]

      for attr <- attrs, sep <- separators, rhs <- right_hand_sides, suffix <- suffixes do
        line = attr <> sep <> rhs <> suffix
        fixed = fix(line)
        rewritten? = fixed != line

        assert length(analyze(line)) == if(rewritten?, do: 1, else: 0),
               "check and fix disagree on #{inspect(line)}"

        if rewritten? do
          in_module = """
          defmodule M do
            #{String.trim_trailing(fixed)}
          end
          """

          assert valid_syntax?(in_module), "did not parse after fix: #{inspect(fixed)}"
        end
      end
    end

    test "every wrappable shape parses after the fix" do
      for line <- [
            "@type t :: () -> any()",
            "@type handler :: () -> {:ok, term()} | {:error, term()}",
            "@type t :: () -> (integer() -> boolean())",
            "@spec run() :: () -> any()",
            "@callback run() :: () -> any()",
            "@opaque t :: () -> any()",
            "@typep p :: () -> any()",
            "@macrocallback m() :: () -> any()",
            "@spec f(t :: integer()) :: () -> any()"
          ] do
        assert valid_syntax?(fix(line)), "did not parse after fix: #{fix(line)}"
        assert analyze(fix(line)) == []
      end
    end
  end
end
