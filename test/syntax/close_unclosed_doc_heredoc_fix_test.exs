defmodule Credence.Syntax.CloseUnclosedDocHeredocFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, module_shape: 1, valid_syntax?: 1]

  alias Credence.Syntax.CloseUnclosedDocHeredoc

  defp analyze(code), do: CloseUnclosedDocHeredoc.analyze(code)
  defp fix(code), do: CloseUnclosedDocHeredoc.fix(code)

  # The lines `analyze/1` reports an unclosed opener on. Every repair case below
  # asserts this beside what the fix does to the same input — with no exception,
  # so a new repair test added without it is visibly out of step — because the
  # check and the fix only agree by *sharing* one boundary scan. A
  # check that drifted back to "is the next non-blank line a `def`?" would keep
  # rewriting the @spec-bounded and prose-bounded docs while silently reporting
  # none of them, and a file that only ever asserts the rewrite stays green
  # through that.
  defp reported_lines(code), do: Enum.map(analyze(code), & &1.meta.line)

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

    assert reported_lines(input) == [2]
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

    assert reported_lines(input) == [2]
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

  # A doc line that *is* a real definition keyword — `defstruct`, `defmodule`,
  # `defimpl` — clears the word boundary that keeps English prose out. But `@doc`
  # documents none of those forms; it attaches to the next function-like
  # definition. So such a line at the doc's own indentation is as plausibly doc
  # prose ("defstruct fields are validated on build") as it is code, and the rule
  # has nothing to tell them apart with. Guessing "code" empties the doc and
  # promotes the line to live module-body code in output that *parses*, so
  # nothing downstream reverts it. The rule declines instead — the same answer it
  # gives to a `\"""` below that it cannot place.
  test "declines when the doc's first line is a definition form @doc cannot document" do
    code = """
    defmodule Sample do
      @doc \"""
      defstruct fields

      def add(a, b), do: a + b
    end
    """

    assert analyze(code) == []
    confirm_fix(fix(code), code)
  end

  # Declining is scoped to the *first* definition-form line below the opener. A
  # `defstruct` further down — past the `def` the doc documents — is not
  # ambiguous at all and must not veto the repair.
  test "still repairs when the documented def comes above a defstruct" do
    input = """
    defmodule Sample do
      @doc \"""
      Adds the two numbers.

      def add(a, b), do: a + b

      defstruct [:total]
    end
    """

    close = "  \"\"\""

    expected = """
    defmodule Sample do
      @doc \"""
      Adds the two numbers.

    #{close}
      def add(a, b), do: a + b

      defstruct [:total]
    end
    """

    assert reported_lines(input) == [2]
    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))
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

    assert reported_lines(input) == [2]
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

    assert reported_lines(input) == [2]
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

  # A non-blank line indented *less* than the `@doc` — the enclosing module's own
  # `end` — proves the block the doc lives in has already closed, so the search
  # for "the definition this doc documents" cannot legitimately continue past it.
  # Scanning on lands the closer inside the *next* module: that module's header
  # and the `end` above it are swallowed into the doc string, the module ceases to
  # exist, and its function is silently re-homed into the first one. The result
  # only warns (an outdented heredoc is not an error), and it parses, so nothing
  # downstream reverts it. There is no second module to close the doc in front of,
  # so the rule declines — the same answer it gives a `\"""` below it cannot place.
  test "does not scan past a line indented less than the @doc into a later module" do
    code = """
    defmodule Helpers do
      @doc \"""
      Shared helpers.
    end

    defmodule Main do
      def run, do: :ok
    end
    """

    assert analyze(code) == []
    confirm_fix(fix(code), code)
  end

  # The bound is the *outdent*, not "stop at the first `end`". An `end` indented
  # deeper than the `@doc` is doc text — the last line of a code example — and
  # must not stop the search for the definition being documented, or the doc is
  # left unclosed and the file still does not parse.
  test "still repairs across an end indented deeper than the @doc" do
    input = """
    defmodule Sample do
      @doc \"""
      Example:

          def add(a, b) do
            a + b
          end

      def add(a, b), do: a + b
    end
    """

    close = "  \"\"\""

    expected = """
    defmodule Sample do
      @doc \"""
      Example:

          def add(a, b) do
            a + b
          end

    #{close}
      def add(a, b), do: a + b
    end
    """

    assert reported_lines(input) == [2]
    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))

    shape = module_shape(fix(input))
    assert shape.docs == ["Example:\n\n    def add(a, b) do\n      a + b\n    end\n\n"]
    assert shape.defs == [{:add, 2}]
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

    assert reported_lines(input) == [2]
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

    assert reported_lines(input) == [2]
    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))

    shape = module_shape(fix(input))
    assert shape.docs == ["Adds the two numbers.\n\n"]
    assert shape.specs == ["add(integer, integer) :: integer"]
    assert shape.defs == [{:add, 2}]
  end

  # The price of ending the doc at a module attribute: a line of doc *prose* that
  # begins with a bare `@word` at exactly the doc's own indentation is read as the
  # end of the doc. The doc is truncated above it and the prose becomes
  # module-body code — and the result parses, so nothing downstream reverts it.
  # That cost is what buys the `@doc` → `@spec` → `def` repair above, so it is
  # pinned rather than fixed: this test is the alarm if the attribute scan is ever
  # widened, and the record of what "widened" would cost.
  test "truncates the doc at a prose line that starts with a bare @word" do
    input = """
    defmodule Sample do
      @doc \"""
      Adds the two numbers.

      @timeout - how long to wait
      def add(a, b), do: a + b
    end
    """

    close = "  \"\"\""

    expected = """
    defmodule Sample do
      @doc \"""
      Adds the two numbers.

    #{close}
      @timeout - how long to wait
      def add(a, b), do: a + b
    end
    """

    assert reported_lines(input) == [2]
    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))

    # The prose line is gone from the doc and is now live module-body code.
    shape = module_shape(fix(input))
    assert shape.docs == ["Adds the two numbers.\n\n"]
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

    assert reported_lines(input) == [2, 5]
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

  # Everything between the opener and the line the closer goes above becomes doc
  # text. A module-level directive sitting there is therefore *deleted* by the
  # repair: `use GenServer` folded into the doc string costs the module its
  # behaviour, its default callbacks and `child_spec/1`. The result parses and
  # compiles (a stale `@impl` only warns), so nothing downstream reverts it —
  # which is why the rule has to decline before emitting it rather than rely on a
  # guard to catch it.
  test "declines when a directive sits between the doc and its def" do
    code = """
    defmodule Server do
      @doc \"""
      Starts the server.
      use GenServer

      def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
    end
    """

    assert reported_lines(code) == []
    confirm_fix(fix(code), code)
  end

  # The same absorption eats a block: an Ecto `schema "users" do … end` between
  # the doc and its `def` is swallowed whole, and with it every field the module
  # declares. The block's body is indented deeper than the `@doc`, so only its
  # opening line is visible at the doc's own indentation — a line ending in `do`.
  test "declines when a do-block opener sits between the doc and its def" do
    code = """
    defmodule User do
      @doc \"""
      A user of the system.

      schema "users" do
        field(:name, :string)
      end

      def changeset(user, attrs), do: cast(user, attrs, [:name])
    end
    """

    assert reported_lines(code) == []
    confirm_fix(fix(code), code)
  end

  # A macro call is module-level code just as much as a directive is, and naming
  # the macros is not an option: the list runs to ~75 entries across Phoenix,
  # Ecto, Absinthe, Ash and Oban, and any library can mint another. So the guard
  # matches on shape. These six pin both shapes it recognises.
  #
  # Each is written the way its own library's documentation writes it — that is
  # the point of listing six rather than one. Around 97% of module-level macro
  # idioms omit the parentheses, so a guard that only saw `name(...)` would miss
  # the common spelling of every one of them.
  for {label, line} <- [
        {"a parenthesised macro call", "plug(:fetch_session)"},
        {"a macro call written without parentheses", "plug :fetch_session"},
        {"an atom first argument followed by a comma", "field :name, :string"},
        {"a capitalised module path as the first argument",
         "action_fallback MyAppWeb.FallbackController"},
        {"a quoted string as the first argument", ~s(get "/users", UserController, :index)},
        {"a parenthesised call with no arguments", "timestamps()"}
      ] do
    test "declines when #{label} sits between the doc and its def" do
      code = """
      defmodule Sample do
        @doc \"""
        Does a thing.

        #{unquote(line)}

        def go(conn), do: conn
      end
      """

      assert reported_lines(code) == []
      confirm_fix(fix(code), code)
    end
  end

  # The shape test is gated on the line carrying no backtick, because doc prose
  # that mentions code almost always quotes it and module-level code never
  # contains one.
  #
  # The fixture has to start with a bare lowercase word for the gate to matter at
  # all: prose that *opens* with a backtick never reaches the shape test, since
  # both branches are anchored on `^[a-z_]`. This one is the shape of the single
  # line in this repo's 5,632 doc-text lines that the gate actually saves —
  # "valid Elixir, so `café =.make_ref()` is the same syntax error as any other"
  # — a word, a capitalised module, a comma, and backticked code after it.
  test "still repairs when doc prose names a module and quotes code in backticks" do
    input = """
    defmodule Sample do
      @doc \"""
      valid Elixir, so `plug :fetch_session` is code and not prose.

      def call(conn, _opts), do: conn
    end
    """

    close = "  \"\"\""

    expected = """
    defmodule Sample do
      @doc \"""
      valid Elixir, so `plug :fetch_session` is code and not prose.

    #{close}
      def call(conn, _opts), do: conn
    end
    """

    assert reported_lines(input) == [2]
    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))
  end

  # The parenthesised branch requires the call to CLOSE on the same line. Drop
  # that and a prose line wrapping mid-expression onto a stray `)` matches too,
  # and the repair is declined instead.
  #
  # On this repo's own 5,632 doc-text lines the requirement saves nothing the
  # backtick gate does not already save — prose here quotes its code. So this
  # fixture is the only thing holding the clause up, and it has to stay
  # backtick-free or the gate would mask what it is testing.
  test "still repairs when doc prose wraps mid-expression onto a stray paren" do
    input = """
    defmodule Sample do
      @doc \"""
      Splits clauses whose guard is short enough that

      length(x) <= 1) and rewrites them into two clauses.

      def split(x), do: x
    end
    """

    close = "  \"\"\""

    expected = """
    defmodule Sample do
      @doc \"""
      Splits clauses whose guard is short enough that

      length(x) <= 1) and rewrites them into two clauses.

    #{close}
      def split(x), do: x
    end
    """

    assert reported_lines(input) == [2]
    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))
  end

  # This guard only ever *narrows* when the rule fires, so the defect to guard
  # against is the opposite of "ships inert": a future widening that quietly
  # stops repairing real files. Fixtures cannot catch that — they are short and
  # prose-y by construction. This runs the rule over every real `@doc` block in
  # `lib/` with its closing quotes deleted, which is the rule's exact failure
  # mode on this repo's own prose.
  #
  # The measured baseline is 52 repairs over 333 broken docs, identical before
  # and after the shape test was added (0 lost, 0 gained, 0 emitted bytes
  # changed). Both assertions are floors, not equalities: `lib/` gains and loses
  # doc blocks constantly, and pinning the exact totals would red this on edits
  # that have nothing to do with the rule. A widening that costs a repair drives
  # the repair count DOWN, which is the direction the floor catches.
  #
  # Tagged `:corpus` so the fix loop's fast gate (`--exclude corpus`) skips it;
  # it still runs in CI, where a whole-repo scan belongs.
  @tag :corpus
  test "repairs the same real docs it did before the shape test" do
    cases =
      Path.wildcard("lib/**/*.ex")
      |> Enum.flat_map(fn path ->
        lines = path |> File.read!() |> String.split("\n")

        lines
        |> Enum.with_index()
        |> Enum.filter(fn {line, _} -> Regex.match?(~r/^\s*@(?:module)?doc\s+"""\s*$/, line) end)
        |> Enum.flat_map(fn {_, opener} ->
          case Enum.find_index(Enum.drop(lines, opener + 1), &(String.trim(&1) == ~s("""))) do
            nil ->
              []

            closer ->
              [
                {"#{path}:#{opener + 1}",
                 Enum.join(List.delete_at(lines, opener + 1 + closer), "\n")}
              ]
          end
        end)
      end)
      |> Enum.reject(fn {_, source} -> valid_syntax?(source) end)

    repaired = for {id, source} <- cases, fix(source) != source, do: id

    assert length(cases) >= 250,
           "only #{length(cases)} broken docs harvested (baseline 333) — the harvester has stopped " <>
             "finding them, so the repair floor below proves nothing"

    assert length(repaired) >= 52,
           "the rule repairs #{length(repaired)}/#{length(cases)} real broken docs, below the 52 " <>
             "baseline — a guard was widened and it cost repairs. Diff against the previous commit " <>
             "before adjusting this number."
  end

  # The closer does not always land above a `def`: an `@spec`/`@impl`/second
  # `@doc` between the doc and its definition ends the doc instead. The reported
  # message has to describe where the repair actually goes, or a reader who acts
  # on it looks for the wrong line.
  test "the reported message describes an attribute boundary too" do
    input = """
    defmodule Sample do
      @doc \"""
      Adds the two numbers.

      @spec add(integer, integer) :: integer
      def add(a, b), do: a + b
    end
    """

    assert [issue] = analyze(input)

    assert issue.message ==
             "Unclosed `@doc \"\"\"` heredoc — the closing `\"\"\"` is missing before the " <>
               "definition or module attribute that follows the doc text."
  end

  # A later doc's closing quotes veto the repair of an earlier broken one. The
  # veto reads the *same unchanged source* every time, so this is not a repair
  # deferred to a later round — no round of this rule will ever repair such a
  # file. Pinned so the moduledoc's known-limitation text stays true: if a second
  # pass ever did repair it, this goes red.
  test "the closing-quotes veto gives the same answer on every round" do
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

    confirm_fix(fix(code), code)
    confirm_fix(fix(fix(code)), code)
    assert analyze(fix(code)) == []
  end

  test "fixed output no longer flags" do
    input = """
    defmodule Solution do
      @doc \"""
      def find_min_max(list) do
        Enum.min_max(list)
      end
    end
    """

    assert reported_lines(input) == [2]
    assert analyze(fix(input)) == []
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

    assert reported_lines(input) == [2, 7]
    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Solution do
      @doc \"""
      def find_min_max(list) do
        Enum.min_max(list)
      end
    end
    """

    assert reported_lines(input) == [2]
    assert valid_syntax?(fix(input))
  end
end
