defmodule Credence.Syntax.FixExtraBraceInEtsMatch do
  @moduledoc """
  Removes the one extra `}` an LLM left before the closing `)` of an `:ets.*`
  call, so the match-spec pattern argument closes where it should.

  ## Bad (won't parse — mismatched delimiter)

      :ets.match(table, {{name, :"$1"}, :"$2"}})

  ## Good

      :ets.match(table, {{name, :"$1"}, :"$2"})

  ## The safe core

  A text scan for the trailing bytes cannot do this job. `"}})` is ordinary
  valid Elixir — `send(pid, {:msg, %{name: "x"}})` contains it — and the source
  reaching this phase fails to parse *somewhere*, so a blanket replace would
  silently break every such call in a file broken for an unrelated reason.
  Worse, the bytes are genuinely ambiguous: the valid nested-tuple pattern

      :ets.match(table, {{name, :"$1"}, {:"$2"}})

  ends in exactly the same four characters as the broken one above.

  So detection is driven by the parser instead, and `analyze/1` and `fix/1`
  share it (`repair/1`) — the rule never flags what it will not fix. Four
  guards have to hold together:

    * **The parser must report this exact mismatch.** `Code.string_to_quoted/2`
      names the delimiters it tripped over; we act only on
      `error_type: :mismatched_delimiter` with a `(` opened, a `}` met and a `)`
      expected. That is the parser telling us this `}` closes nothing, and a
      `}` inside a string, heredoc, sigil or comment can never be the reported
      token.

    * **The offending `}` must be the second of `}})`.** The parser hands back
      the exact line and column of the token, and we act only when the previous
      character is `}` and the next is `)` — the "one brace too many closing a
      nested tuple argument" shape. `f(a, b}, c)` and friends are somebody
      else's repair.

    * **The opening `(` must belong to an `:ets.` call.** The same metadata
      carries the position of the `(`, so we can require `:ets.<fun>`
      immediately before it. Extra braces elsewhere are left for a sister rule
      rather than claimed by a rule whose name promises ETS.

    * **Only the parser-reported error is repaired.** The rest of the file may
      still be malformed; later syntax passes can repair the next error.

  Deleting the reported closer is the minimal edit: nothing else in the file
  moves, and every character the tokenizer had already accepted stays where it
  was.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @impl true
  def analyze(source) do
    case repair(source) do
      {:fixed, _fixed, line} ->
        [
          %Issue{
            rule: :fix_extra_brace_in_ets_match,
            message:
              "Extra `}` before `)` in an `:ets.*` match spec pattern — the argument is already closed.",
            meta: %{line: line}
          }
        ]

      :no_fix ->
        []
    end
  end

  @impl true
  def fix(source) do
    case repair(source) do
      {:fixed, fixed, _line} -> fixed
      :no_fix -> source
    end
  end

  # Single source of truth for both callbacks: either we have a guarded
  # deletion, or there is nothing to report.
  defp repair(source) do
    with {:ok, open_line, open_col, line_no, col} <- detect(source),
         lines = String.split(source, "\n"),
         :ok <- check_ets_call(lines, open_line, open_col),
         :ok <- check_shape(lines, line_no, col),
         {:ok, fixed} <- delete_brace(lines, line_no, col) do
      {:fixed, fixed, line_no}
    else
      _ -> :no_fix
    end
  end

  # Ask the parser whether it met a `}` where the `)` of a call was due, and
  # where both delimiters sit.
  defp detect(source) do
    case Code.string_to_quoted(source, columns: true) do
      {:error, {meta, _message, _token}} when is_list(meta) ->
        open_line = Keyword.get(meta, :line)
        open_col = Keyword.get(meta, :column)
        line_no = Keyword.get(meta, :end_line)
        col = Keyword.get(meta, :end_column)

        if Keyword.get(meta, :error_type) == :mismatched_delimiter and
             Keyword.get(meta, :opening_delimiter) == :"(" and
             Keyword.get(meta, :closing_delimiter) == :"}" and
             Keyword.get(meta, :expected_delimiter) == :")" and
             is_integer(open_line) and is_integer(open_col) and
             is_integer(line_no) and is_integer(col) do
          {:ok, open_line, open_col, line_no, col}
        else
          :none
        end

      _ ->
        :none
    end
  end

  # The `(` the parser was trying to close must be the one opening an `:ets.`
  # call, so the rule stays inside the scope its name promises.
  defp check_ets_call(lines, open_line, open_col) do
    with {:ok, chars} <- line_chars(lines, open_line),
         "(" <- at(chars, open_col - 1) do
      prefix = chars |> Enum.take(open_col - 1) |> List.to_string()
      if Regex.match?(~r/:ets\.\w+$/, prefix), do: :ok, else: :none
    else
      _ -> :none
    end
  end

  # `}})` — one brace too many closing a nested tuple argument. The reported
  # token is the second `}`; anything else is a different repair.
  defp check_shape(lines, line_no, col) do
    with {:ok, chars} <- line_chars(lines, line_no),
         "}" <- at(chars, col - 1),
         "}" <- at(chars, col - 2),
         ")" <- at(chars, col) do
      :ok
    else
      _ -> :none
    end
  end

  # Drop the reported `}`. Nothing else in the file moves; another syntax error
  # may remain for a later pass.
  defp delete_brace(lines, line_no, col) do
    {:ok, chars} = line_chars(lines, line_no)
    repaired = chars |> List.delete_at(col - 1) |> List.to_string()

    candidate =
      lines
      |> List.replace_at(line_no - 1, repaired)
      |> Enum.join("\n")

    {:ok, candidate}
  end

  # The parser counts columns in graphemes, not bytes and not codepoints: a
  # combining accent, a ZWJ emoji and a flag are each one column (checked in the
  # tests). Splitting the same way keeps the offset aligned; were it ever not,
  # the shape guard would see the wrong character and the rule would stay silent.
  defp line_chars(lines, line_no) do
    case Enum.at(lines, line_no - 1) do
      nil -> :none
      line -> {:ok, String.graphemes(line)}
    end
  end

  defp at(_chars, index) when index < 0, do: nil
  defp at(chars, index), do: Enum.at(chars, index)
end
