defmodule Credence.Syntax.CloseUnclosedDocHeredocFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, module_shape: 1, valid_syntax?: 1]

  alias Credence.Syntax.CloseUnclosedDocHeredoc

  defp analyze(code), do: CloseUnclosedDocHeredoc.analyze(code)
  defp fix(code), do: CloseUnclosedDocHeredoc.fix(code)

  test "fixes unclosed @doc heredoc by inserting closing quotes" do
    input = """
    defmodule Solution do
      @doc \"""
      def find_min_max(list) do
        Enum.min_max(list)
      end
    end
    """

    close = "  \"\"\""

    expected = """
    defmodule Solution do
      @doc \"""
    #{close}
      def find_min_max(list) do
        Enum.min_max(list)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes unclosed @doc heredoc with blank lines before def" do
    input = """
    defmodule Solution do
      @doc \"""

      def find_min_max(list) do
        Enum.min_max(list)
      end
    end
    """

    close = "  \"\"\""

    expected = """
    defmodule Solution do
      @doc \"""

    #{close}
      def find_min_max(list) do
        Enum.min_max(list)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "does not modify properly closed @doc heredoc" do
    code = """
    defmodule Solution do
      @doc \"\"\"
      Finds the min and max.
      \"\"\"
      def find_min_max(list) do
        Enum.min_max(list)
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  # A correctly closed `@doc """` is off limits no matter what its first content
  # line looks like. The rule only ever sees source that does not parse, so a
  # file like this one reaches it whenever some *other* line has a syntax error —
  # and rewriting it would empty the doc, promote the documented example to real
  # code, and turn the doc's own closing `"""` into an opening one that swallows
  # the code below. What holds the line is the "is there a `\"""` further down?"
  # guard, so these two cases pin it directly.
  test "leaves a closed @doc heredoc alone when its first content line is a def example" do
    code = """
    defmodule Solution do
      @doc \"\"\"
      def example do
        :ok
      end
      \"\"\"
      def a, do: 1

      @doc \"\"\"
      Docs for b.
      \"\"\"
      def b, do: 2
    end
    """

    assert analyze(code) == []
    confirm_fix(fix(code), code)
  end

  test "leaves a closed @doc heredoc alone when its first content line starts with \"def\"" do
    code = """
    defmodule Solution do
      @doc \"\"\"
      defaults to 0 when the key is absent.
      \"\"\"
      def get(map, key), do: Map.get(map, key)
    end
    """

    assert analyze(code) == []
    confirm_fix(fix(code), code)
  end

  # "def" as the first three letters of an English word is not a definition. The
  # rule exists to close a doc *before the next definition*; with no definition
  # below there is nothing to close before, and firing anyway empties the doc and
  # spills its prose into the module body.
  test "does not treat prose beginning with \"def\" as the next definition" do
    code = """
    defmodule Sample do
      def get(map, key), do: Map.get(map, key)

      @doc \"\"\"
      defaults to 0 when the key is absent.
    end
    """

    assert analyze(code) == []
    confirm_fix(fix(code), code)
  end

  # The same false match, but here the rewrite's output *parses*: the doc is
  # silently emptied and its body becomes live code, which no downstream progress
  # guard can see (a source that parses is never reverted).
  test "does not treat a `defaults = ...` binding as the next definition" do
    code = """
    defmodule Sample do
      @doc \"\"\"
      1 + 1

      defaults = %{a: 1}
    end
    """

    assert analyze(code) == []
    confirm_fix(fix(code), code)
  end

  # The rule's whole purpose is to close a doc *before the next definition*. When
  # the doc actually has text in it — the LLM wrote the doc and forgot the closer,
  # which is the shape the moduledoc describes — the first non-blank line below
  # the opener is that text, not the `def`. Closing above the text empties the doc
  # and turns its content into live module-body code.
  test "closes the doc under its own text, not above it" do
    input = """
    defmodule Sample do
      @doc \"""
      Adds the two numbers.

      def add(a, b), do: a + b
    end
    """

    close = "  \"\"\""

    expected = """
    defmodule Sample do
      @doc \"""
      Adds the two numbers.

    #{close}
      def add(a, b), do: a + b
    end
    """

    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))
    assert analyze(fix(input)) == []
  end

  # The same defect with doc text that happens to be valid Elixir: closing above
  # it produces a source that *parses*, so no downstream progress guard can see
  # that the doc was emptied and `1 + 1` promoted to real code.
  test "does not promote doc text to module-body code" do
    input = """
    defmodule Sample do
      @doc \"""
      1 + 1

      def get(m, k), do: Map.get(m, k)
    end
    """

    close = "  \"\"\""

    expected = """
    defmodule Sample do
      @doc \"""
      1 + 1

    #{close}
      def get(m, k), do: Map.get(m, k)
    end
    """

    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))
  end

  # `closing_quotes_below?` scans to the end of the file, so a *later* correctly
  # closed doc vetoes the repair of an earlier broken one. That is a real
  # limitation (documented in the moduledoc), not a bound the `"""` scan stops at:
  # pinned here so that "the scan stops at the next definition" is never read into
  # the code again.
  test "declines the repair when a later doc's closing quotes appear below" do
    code = """
    defmodule Sample do
      @doc \"""
      Docs for a.
      def a, do: 1

      @doc \"""
      Docs for b.
      \"""
      def b, do: 2
    end
    """

    assert analyze(code) == []
    confirm_fix(fix(code), code)
  end

  # A `def` example written *inside* the doc text is indented deeper than the
  # `@doc` line that opened the doc. Reading it as "the next definition" closes
  # the doc above it: the doc is truncated to the prose before the example and
  # the example itself becomes a second, live clause of the function. The output
  # parses, so nothing downstream can revert it — hence the assertions below read
  # the doc and the clause list back off the string the rule actually emitted.
  test "does not close the doc above a def example indented inside the doc text" do
    input = """
    defmodule Sample do
      @doc \"""
      Example:

          def add(a, b), do: a + b
      def add(a, b), do: a + b
    end
    """

    expected = """
    defmodule Sample do
      @doc \"""
      Example:

          def add(a, b), do: a + b
      \"""
      def add(a, b), do: a + b
    end
    """

    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))

    shape = module_shape(fix(input))
    assert shape.docs == ["Example:\n\n    def add(a, b), do: a + b\n"]
    assert shape.defs == [{:add, 2}]
  end

  # `@doc` → `@spec` → `def` is the ordering this rule exists to repair. Scanning
  # past the `@spec` to the `def` puts the closer below the attribute, so the
  # spec's text ends up inside the doc string and the `@spec` itself is gone. The
  # result parses and compiles without a warning, so the deleted contract is
  # invisible to every downstream guard.
  test "closes the doc above an @spec that sits between the doc and its def" do
    input = """
    defmodule Sample do
      @doc \"""
      Adds the two numbers.

      @spec add(integer, integer) :: integer
      def add(a, b), do: a + b
    end
    """

    expected = """
    defmodule Sample do
      @doc \"""
      Adds the two numbers.

      \"""
      @spec add(integer, integer) :: integer
      def add(a, b), do: a + b
    end
    """

    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))

    shape = module_shape(fix(input))
    assert shape.docs == ["Adds the two numbers.\n\n"]
    assert shape.specs == ["add(integer, integer) :: integer"]
    assert shape.defs == [{:add, 2}]
  end

  # Two unclosed openers with no `\"""` anywhere below them must not resolve to
  # the same insertion point: two closers stacked on one line terminate the first
  # doc and re-open a heredoc that runs to the end of the file, so the output can
  # never parse and the whole round — including other rules' repairs to the same
  # file — is discarded. The second opener is where the first doc ends.
  test "gives each unclosed doc its own closer when both share the next def" do
    input = """
    defmodule Sample do
      @doc \"""
      Docs for a.

      @doc \"""
      More docs.
      def a, do: 1
    end
    """

    expected = """
    defmodule Sample do
      @doc \"""
      Docs for a.

      \"""
      @doc \"""
      More docs.
      \"""
      def a, do: 1
    end
    """

    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))

    shape = module_shape(fix(input))
    assert shape.docs == ["Docs for a.\n\n", "More docs.\n"]
    assert shape.defs == [{:a, 0}]
  end

  # Nothing below the opener bounds the "is there a `\"""` further down?" veto —
  # in particular a blank line does not stop the scan. Pinned so the veto's answer
  # stays the same now that the scan says so in one line.
  test "declines the repair when a blank line precedes the closing quotes below" do
    code = """
    defmodule Sample do
      @doc \"""

      Docs for a.
      def a, do: 1

      @doc \"""
      Docs for b.
      \"""
      def b, do: 2
    end
    """

    assert analyze(code) == []
    confirm_fix(fix(code), code)
  end

  test "fixed output no longer flags" do
    assert analyze(
             fix("""
             defmodule Solution do
               @doc \"""
               def find_min_max(list) do
                 Enum.min_max(list)
               end
             end
             """)
           ) == []
  end

  test "closes every unclosed @doc heredoc in a module" do
    input = """
    defmodule Solution do
      @doc \"""
      def a(x) do
        x
      end

      @doc \"""
      def b(x) do
        x
      end
    end
    """

    expected = """
    defmodule Solution do
      @doc \"""
      \"""
      def a(x) do
        x
      end

      @doc \"""
      \"""
      def b(x) do
        x
      end
    end
    """

    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             defmodule Solution do
               @doc \"""
               def find_min_max(list) do
                 Enum.min_max(list)
               end
             end
             """)
           )
  end
end
