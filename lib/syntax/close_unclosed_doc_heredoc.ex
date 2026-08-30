defmodule Credence.Syntax.CloseUnclosedDocHeredoc do
  @moduledoc """
  Detects and fixes unclosed `@doc` heredocs where the LLM jumps
  straight into function code without ever closing the triple-quote block.

  LLMs frequently emit `@doc` followed by triple-quotes on their own
  line and then immediately write a `def` on the next non-blank line
  without a closing set of triple-quotes in between. This causes a
  `TokenMissingError` (missing terminator). The fix inserts a closing
  triple-quote line — indented to match the `@doc` line — immediately
  before the line where the doc text ends: the `def` being documented, or
  a module attribute (`@spec`, `@impl`, a second `@doc`) sitting between
  the doc and that `def`. Only lines at the `@doc`'s own indentation
  count, so a `def` example written *inside* the doc stays inside it.

  ## Bad (won't parse — TokenMissingError)

      defmodule Solution do
        @doc \"\"\"
        def find_min_max(list) do
          Enum.min_max(list)
        end
      end

  ## Good

      defmodule Solution do
        @doc \"\"\"
        \"\"\"
        def find_min_max(list) do
          Enum.min_max(list)
        end
      end

  ## Known limitation

  The rule declines whenever *any* triple-quote line appears below the opener,
  which is what keeps it off a correctly closed doc it cannot otherwise tell
  apart. The cost is that a file with a broken doc above `def a` and a correctly
  closed doc above `def b` is never repaired: the second doc's closing quotes
  veto the repair of the first. Nothing in this rule will ever repair such a
  file — the veto reads the same unchanged source every time, so a later round
  returns the same decline.

  The search for that definition stops at the first non-blank line indented less
  than the `@doc` — the enclosing module's own `end`. A file whose broken doc has
  no definition left inside its own module is therefore declined rather than
  closed in front of a `def` belonging to a later module.

  It declines for the same reason when the first definition below the opener is a
  form `@doc` cannot document (`defstruct`, `defmodule`, `defimpl`, …): such a
  line is as plausibly doc prose as it is code, and the rule has nothing to tell
  them apart with.

  It declines, too, when the lines that would become doc text include module-level
  code the doc must not swallow — a `use`/`import`/`alias`/`require` directive, a
  `defn`, a line opening a `do` block such as an Ecto `schema`, or a macro call
  recognised by its shape: a parenthesised call closing on the same line
  (`timestamps()`, `plug(:fetch_session)`), or a bare word whose first argument is
  an atom, a quoted string, a capitalised module path or a capture and ends at a
  comma or end of line (`plug :fetch_session`, `field :name, :string`,
  `action_fallback MyAppWeb.FallbackController`). Closing the doc below such a
  line deletes it, and the result still parses and compiles, so nothing
  downstream would notice the loss.

  Those two shapes are matched only on a line carrying no backtick, so doc prose
  that quotes code — ``` `plug :fetch_session` sets up the session ``` — still
  repairs.

  ### What the shape test still swallows

  Matching on shape rather than on a list of macro names is deliberate: the list
  would run to roughly seventy-five entries across Phoenix, Ecto, Absinthe, Ash
  and Oban, and any library can mint a new one. The shapes above cover 36 of 47
  catalogued module-level idioms. The eleven they miss all have a first argument
  that is a list, a tuple, a struct, a bare identifier or a nested lowercase
  call, plus capitalised remote calls:

      create unique_index(:users, [:email])   drop table(:legacy_users)
      validate present(:email)                change set_attribute(:status, :active)
      pipe_through [:api, :auth]              interfaces [:named_entity]
      setup [:create_user]                    prop label, :string
      require_atomic? false                   on_mount {MyAppWeb.UserAuth, :ensure}
      Mox.defmock(MyMock, for: Behaviour)

  A line spelling one of those between a doc and its `def` is still folded into
  the doc string and deleted. Widening further has a real cost in declined
  repairs and no corpus here to measure it against — this repo contains no DSL
  code — so the gap is recorded rather than guessed at.

  Separately, `@def_word` only spells Elixir's own `def…` forms, so a
  library-minted definition macro written without parentheses
  (`deftransform foo(x), do: x`) is recognised as neither a definition nor code
  and is swallowed. The parenthesised spelling (`defsequence(:reset, 0)`) is
  caught by the shape test above.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @doc_heredoc_open ~r/^(\s*)@doc\s+"""\s*$/

  # A line that opens a definition, matched against the line with its indentation
  # already stripped. The trailing `\b` is what keeps English prose out: without
  # it `defaults to 0 when absent.` — an ordinary first line of doc text — counts
  # as "the next def", and the rule then closes the heredoc above it, emptying the
  # doc and spilling its prose into the module body. Every `def…` form Elixir
  # defines is listed so that no real definition stops being recognised. Order
  # within the alternation does not matter: `\b` rejects any alternative that
  # stops mid-word, so `defmacrop` cannot be read as `defmacro` plus a stray `p` —
  # the engine backtracks to the spelling that ends on a word boundary.
  @def_word ~r/^def(?:p|macrop|macro|guardp|guard|delegate|module|protocol|impl|struct|exception|overridable)?\b/

  # The subset of `@def_word` that `@doc` actually documents: it attaches to the
  # next function-like definition, never to a `defmodule`/`defstruct`/`defimpl`/
  # `defprotocol`/`defexception`/`defoverridable`. Those forms are still real
  # definitions, so `@def_word` still finds them — but a line spelling one at the
  # doc's own indentation is as plausibly doc prose (`defstruct fields are
  # validated on build`) as it is code, and nothing in the line tells the two
  # apart. Guessing "code" empties the doc and promotes the prose to module-body
  # code in output that parses, so nothing downstream reverts it. The rule
  # declines instead, the same answer it gives a `"""` below it cannot place.
  @documented_def_word ~r/^def(?:p|macrop|macro|guardp|guard|delegate)?\b/

  # A module attribute, likewise matched with the indentation stripped. An
  # attribute at the module's own indentation ends the doc above it: `@doc` →
  # `@spec`/`@impl` → `def` is the ordering LLMs emit most often, and scanning
  # past the attribute to the `def` would fold the attribute's text into the doc
  # string and delete the attribute itself. A second `@doc """` counts too, which
  # is what stops two unclosed openers from claiming the same insertion point.
  # The cost is doc *prose* whose line begins with a bare `@word` at exactly the
  # module's indentation, which is read as the end of the doc; prose normally
  # writes such a mention inline or in backticks.
  @attribute_word ~r/^@\w+\b/

  # Module-level code that is neither a definition nor an attribute: Elixir's four
  # directives, Nx's `defn`/`defnp`, and any line that opens a `do` block (Ecto's
  # `schema "users" do`, a `test "…" do`, any library macro). Matched with the
  # indentation stripped, like the two above.
  #
  # Everything between the opener and the line the closer goes above becomes doc
  # text, so a line like this one at the `@doc`'s own indentation is *deleted* by
  # the repair. `use GenServer` folded into a doc string costs the module its
  # behaviour, its default callbacks and `child_spec/1`; a swallowed `schema` block
  # takes every field with it. The output parses and compiles (a stale `@impl`
  # only warns), so nothing downstream reverts it. The rule declines instead — the
  # same answer it gives an undocumentable definition form.
  #
  # The `do`-suffix branch also declines on doc prose whose line happens to end in
  # the word "do". Declining costs a repair; swallowing costs the block.
  #
  # Naming the macros instead would be an unbounded list: ~75 names across
  # Phoenix, Ecto, Absinthe, Ash, Oban and friends, and any library can mint a
  # new one (this checkout's own `deps/bunt` writes `defsequence(:reset, 0)`
  # directly under an `@doc`). The `defn|defnp` above are already that list's
  # second version. So the last two branches match on *shape*, not on names:
  #
  #   * a parenthesised call that closes on the same line — `timestamps()`,
  #     `plug(:fetch_session)`. The same-line close is what separates those from
  #     a prose line that wraps mid-expression onto a stray `)`
  #     (`length(x) <= 1) and rewrites them into two clauses`). On this repo's
  #     own doc text it saves nothing the backtick gate below does not already
  #     save, so it is a second line of defence for prose that does not quote
  #     its code; the fix battery pins it with a fixture.
  #   * a bare word whose first argument terminates at a comma or end of line and
  #     is an atom, a quoted string, a capitalised module path, or a capture —
  #     `plug :fetch_session`, `field :name, :string`,
  #     `action_fallback MyAppWeb.FallbackController`. Around 97% of module-level
  #     macro idioms are written without parentheses, so this is the branch that
  #     does the work; the parenthesised form is the exception.
  #
  # Both are gated on the line carrying no backtick anywhere. Real module-level
  # code never contains one; doc prose that quotes code almost always does, so
  # `` `plug :fetch_session` sets up the session `` still repairs.
  #
  # Measured over the 5,608 doc-text lines at a `@doc`'s own indentation in this
  # repo's `lib/`: 3 false declines, which is what the `\bdo$` branch alone
  # already costs, for 36 of 47 catalogued macro idioms instead of none. The 11
  # it still misses are in the known-limitations section of the moduledoc.
  @module_code_word ~r/^(?:use|import|alias|require|defn|defnp)\b|\bdo$|^(?!.*`)(?:[a-z_][A-Za-z0-9_]*\(.*\)[ \t]*$|[a-z_][A-Za-z0-9_]*[ \t]+(?::[a-zA-Z_][A-Za-z0-9_]*[?!]?|"[^"]*"|[A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*|&[A-Z][A-Za-z0-9_.]*\/\d+)[ \t]*(?:,|$))/

  @impl true
  def analyze(source) do
    lines = String.split(source, "\n")

    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if unclosed_doc_heredoc?(line, line_no, lines) do
        [
          %Issue{
            rule: :close_unclosed_doc_heredoc,
            # Not "before the next `def`": the closer lands above whichever line
            # ends the doc text, which is the `def` being documented *or* an
            # `@spec`/`@impl`/second `@doc` sitting above it.
            message:
              "Unclosed `@doc \"\"\"` heredoc — the closing `\"\"\"` is missing before the " <>
                "definition or module attribute that follows the doc text.",
            meta: %{line: line_no}
          }
        ]
      else
        []
      end
    end)
  end

  @impl true
  def fix(source) do
    lines = String.split(source, "\n")

    # Collect {insert_before_index, indent} for every unclosed @doc """
    insertions =
      lines
      |> Enum.with_index()
      |> Enum.flat_map(fn {line, idx} ->
        case Regex.run(@doc_heredoc_open, line) do
          [_, indent] ->
            remaining = Enum.drop(lines, idx + 1)

            offset = doc_end_offset(remaining, indent)

            if offset && not closing_quotes_below?(remaining) do
              [{idx + 1 + offset, indent}]
            else
              []
            end

          _ ->
            []
        end
      end)

    # Apply insertions (sorted descending so indices stay valid)
    sorted = Enum.sort_by(insertions, &elem(&1, 0), :desc)

    Enum.reduce(sorted, lines, fn {insert_at, indent}, acc ->
      {before, after_} = Enum.split(acc, insert_at)
      before ++ [indent <> ~s(""")] ++ after_
    end)
    |> Enum.join("\n")
  end

  defp unclosed_doc_heredoc?(line, line_no, lines) do
    case Regex.run(@doc_heredoc_open, line) do
      [_, indent] ->
        remaining = Enum.drop(lines, line_no)
        doc_end_offset(remaining, indent) != nil and not closing_quotes_below?(remaining)

      _ ->
        false
    end
  end

  # How far below this `@doc` heredoc opener the doc text ends, or `nil` when the
  # rule declines. This is both the admission test and the insertion point: the
  # closing `"""` goes immediately above *this* line. Taking the first non-blank
  # line instead would put the terminator above the doc's own text, emptying the
  # doc and promoting its content to module-body code.
  #
  # There must be a definition below at the `@doc`'s own indentation, otherwise
  # there is nothing to close the heredoc in front of. Anchoring to that indent is
  # what keeps a `def` example *inside* the doc text — indented deeper, as an
  # example is — from being read as the definition being documented. The doc then
  # ends at the first module attribute above that definition, if any: everything
  # between the opener and that line is doc text, however it is spelled.
  defp doc_end_offset(lines, indent) do
    lines = Enum.take_while(lines, &inside_doc_block?(&1, indent))

    case Enum.find_index(lines, &at_indent?(&1, indent, @def_word)) do
      nil ->
        nil

      def_offset ->
        if at_indent?(Enum.at(lines, def_offset), indent, @documented_def_word) do
          end_offset = attribute_end_offset(lines, indent, def_offset)

          if not swallows_module_code?(lines, indent, end_offset), do: end_offset
        end
    end
  end

  # Would closing the doc at `end_offset` fold module-level code into the doc
  # string? Those first `end_offset` lines are the doc's body once the closer goes
  # in, and anything among them that is really code is deleted by the repair — see
  # `@module_code_word`. Only lines at the `@doc`'s own indentation count, so a
  # code example written *inside* the doc, indented deeper, is still doc text.
  defp swallows_module_code?(lines, indent, end_offset) do
    lines
    |> Enum.take(end_offset)
    |> Enum.any?(&at_indent?(&1, indent, @module_code_word))
  end

  # Where the doc ends given the definition it documents at `def_offset`: the
  # first module attribute above that definition, if any, else the definition
  # itself.
  defp attribute_end_offset(lines, indent, def_offset) do
    attribute_offset =
      lines
      |> Enum.take(def_offset)
      |> Enum.find_index(&at_indent?(&1, indent, @attribute_word))

    attribute_offset || def_offset
  end

  # Is `line` still inside the block the `@doc` was written in? A non-blank line
  # indented *less* than the `@doc` — the enclosing module's own `end` — proves
  # that block has already closed, so the search for the definition this doc
  # documents must stop there. Scanning on finds a `def` in the *next* module and
  # puts the closer inside it: the `end`, the blank line and the second module's
  # header are all absorbed into the doc string, that module ceases to exist and
  # its function is silently re-homed into the first one. An outdented heredoc is
  # only a warning, and the result parses, so nothing downstream reverts it.
  # Blank lines carry no indentation and never end the block.
  defp inside_doc_block?(line, indent) do
    String.trim(line) == "" or String.starts_with?(line, indent)
  end

  # Does `line` match `word_regex` at exactly `indent`? Deeper-indented lines are
  # doc text (examples), not module-body code.
  defp at_indent?(line, indent, word_regex) do
    case Regex.run(~r/^(\s*)(.*)$/, line) do
      [_, ^indent, rest] -> Regex.match?(word_regex, rest)
      _ -> false
    end
  end

  # Is there a triple-quote line anywhere below? This is what keeps the rule off a
  # *correctly closed* `@doc` heredoc — including one whose first content line is a
  # `def` example, where inserting a terminator would empty the doc, promote the
  # example to real code, and leave the doc's own closing quotes opening a
  # heredoc that swallows the rest of the file. Like `doc_end_offset/2` it scans
  # to the end of the file: nothing below bounds it, neither a blank line nor a
  # definition — see the moduledoc's known limitation.
  defp closing_quotes_below?(lines) do
    Enum.any?(lines, &Regex.match?(~r/^\s*"""/, &1))
  end
end
