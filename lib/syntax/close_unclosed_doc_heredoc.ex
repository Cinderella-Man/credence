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
  veto the repair of the first. Such a file is left to the next round.
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
            message:
              "Unclosed `@doc \"\"\"` heredoc — the closing `\"\"\"` is missing before the next `def`.",
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
    case Enum.find_index(lines, &at_indent?(&1, indent, @def_word)) do
      nil ->
        nil

      def_offset ->
        attribute_offset =
          lines
          |> Enum.take(def_offset)
          |> Enum.find_index(&at_indent?(&1, indent, @attribute_word))

        attribute_offset || def_offset
    end
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
