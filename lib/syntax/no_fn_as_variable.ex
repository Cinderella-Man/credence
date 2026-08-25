defmodule Credence.Syntax.NoFnAsVariable do
  @moduledoc """
  Repairs the syntax error where `fn` is used as a variable name instead of a
  proper identifier like `func`.

  Since `fn` is a reserved keyword in Elixir (it opens an anonymous function),
  using it as a variable name causes `MismatchedDelimiterError` or a
  "missing terminator: end" error: the parser treats `fn` as the start of an
  anonymous function and expects `end`, but finds `]`, `}`, or end-of-input.

  The repair renames `fn` → `func` at the position the *parser* points at, and
  only commits when the whole file parses afterwards.

  ## Bad (won't parse — MismatchedDelimiterError)

      def foo([fn | rest]), do: fn

  ## Good

      def foo([func | rest]), do: func

  ## What this rule deliberately does not touch

  `fn` is far more often a genuine keyword than a variable name, so every
  replacement needs *positional evidence from the parser*:

    * A mismatched `fn … ]` / `fn … }` — a `fn` that a list/tuple delimiter
      closed is pinned to an exact `{line, column}`.
    * A bare `fn` with no closing delimiter at all (`x = fn`) — likewise pinned.
      An `fn` closed by `)` is left to `Credence.Syntax.NoUnclosedFnDelimiter`.
    * A `do` block missing its `end` — there is no column to work from, so the
      only clue is a line that is nothing but `fn`. That guess is allowed
      **only after** one of the pinned replacements above already proved this
      file uses `fn` as an identifier; on its own it would happily rename a
      multi-clause `fn` (which `mix format` puts on its own line) or a `fn`
      inside a `@moduledoc` heredoc.

  Two more guards keep a rename from changing meaning:

    * If the source already uses `func` anywhere, the rule does nothing —
      renaming would silently merge two distinct variables (`def foo(func,
      [fn | rest])` would become a pattern that forces the two to be equal).
    * Every pass must move the parser's error. A replacement that leaves the
      exact same parse error changed nothing the parser can see — which is what
      editing string/heredoc content looks like — so the repair is abandoned
      rather than allowed to ride along with a later, useful pass.
  """
  use Credence.Syntax.Rule

  alias Credence.{Issue, SourceMask}

  # Bound on the repair loop (one iteration per `fn` replacement).
  @max_passes 20

  @impl true
  def analyze(source) do
    case repair(source) do
      {:fixed, _fixed, line} ->
        [
          %Issue{
            rule: :no_fn_as_variable,
            message: "`fn` used as a variable name; renamed to `func`",
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

  # Shared logic: try to repair, commit only when the result actually parses.
  defp repair(source) do
    if taken?(source, "func") do
      :no_fix
    else
      {fixed, line} = do_fix(source, 0, false, nil)

      if fixed != source and parses?(fixed) do
        {:fixed, fixed, line}
      else
        :no_fix
      end
    end
  end

  # Iteratively replace `fn` → `func` at the position the parser reports, one
  # token per pass, until the code parses or we run out of evidence/budget.
  # `evidence?` records whether a parser-pinpointed replacement already happened
  # in this run; `line` is the first line we touched (for the issue metadata).
  defp do_fix(source, pass, evidence?, line) when pass < @max_passes do
    case Code.string_to_quoted(source, columns: true) do
      {:ok, _} ->
        {source, line}

      {:error, {meta, _msg, _token}} when is_list(meta) ->
        with {:ok, fn_line, col} <- find_fix_position(source, meta, evidence?),
             {:ok, fixed} <- replace_at(source, fn_line, col),
             :ok <- progressed?(fixed, meta) do
          do_fix(fixed, pass + 1, true, line || fn_line)
        else
          _ -> {source, line}
        end

      _ ->
        {source, line}
    end
  end

  defp do_fix(source, _pass, _evidence?, line), do: {source, line}

  # A pass that leaves the parser reporting the very same error moved nothing
  # the parser can see — the edit landed in string/heredoc/comment content, not
  # in code. Stop, so that edit can never ride along with a later useful pass.
  defp progressed?(fixed, meta) do
    case Code.string_to_quoted(fixed, columns: true) do
      {:error, {^meta, _msg, _token}} -> :halt
      _ -> :ok
    end
  end

  # Determine where a `fn` → `func` replacement should happen based on the
  # parser error metadata. Returns `{:ok, line, col}` or `:none`.
  defp find_fix_position(source, meta, evidence?) do
    cond do
      # `fn` mismatched with `]` or `}` — `fn` used as a variable inside a list
      # or tuple. The parser pins the opening `fn` itself.
      Keyword.get(meta, :error_type) == :mismatched_delimiter and
        Keyword.get(meta, :opening_delimiter) == :fn and
          Keyword.get(meta, :closing_delimiter) in [:"]", :"}"] ->
        {:ok, Keyword.get(meta, :line), Keyword.get(meta, :column)}

      # `fn` with no closing delimiter at all — a bare `fn` used as a value
      # (`x = fn`, `fn = 1`). An `fn` closed by `)` belongs to
      # `NoUnclosedFnDelimiter`, so require the absence of a closing delimiter.
      Keyword.get(meta, :opening_delimiter) == :fn and
        Keyword.get(meta, :expected_delimiter) == :end and
          Keyword.get(meta, :closing_delimiter) == nil ->
        {:ok, Keyword.get(meta, :line), Keyword.get(meta, :column)}

      # A `do` block missing its `end` — the parser consumed that `end` for a
      # stray `fn`. There is no column here, only the heuristic "a line that is
      # nothing but `fn`", so require prior evidence that this file really does
      # use `fn` as an identifier.
      evidence? and
        Keyword.get(meta, :opening_delimiter) == :do and
          Keyword.get(meta, :expected_delimiter) == :end ->
        find_standalone_fn(source)

      true ->
        :none
    end
  end

  # Find an `fn` the parser misread as the keyword, in a line the error metadata
  # gives no column for. Two shapes, both requiring `evidence?` at the call site
  # — a pinned replacement must already have proved this file uses `fn` as an
  # identifier. A line whose next non-blank neighbour is a `->` clause is skipped
  # in both: that is a multi-clause anonymous function, not a variable.
  #
  # ## Why the second shape exists (escalation ledger row 164)
  #
  # Only "a line that is nothing but `fn`" was recognised. That is what a `fn`
  # variable looks like in a MODULE-LESS snippet — and every one of this rule's
  # fixtures is module-less, so the gap was invisible to its own tests.
  #
  # Real code has a `defmodule`. Wrap the moduledoc's own Bad example in one and
  # the rule stops firing entirely: after the first (pinned) rename, the
  # remaining `fn` sits at the END of `def foo([func | rest]), do: fn`, and the
  # parser now blames the unterminated `defmodule do` — no column, and the line
  # is not "nothing but fn". Reproduced live on the ledger's own source.
  defp find_standalone_fn(source) do
    lines = SourceMask.lines(source)

    lines
    |> Enum.with_index()
    |> Enum.find_value(:none, fn {{line, shadow}, idx} ->
      cond do
        # `fn.(v)` / `fn.field` — the keyword can never be followed by a dot, so
        # this needs no clause check and no positional evidence to be certain.
        col = called_fn_column(shadow) -> {:ok, idx + 1, col}
        clause_follows?(lines, idx) -> nil
        String.trim(line) == "fn" -> {:ok, idx + 1, find_fn_column(line)}
        col = value_position_fn_column(line) -> {:ok, idx + 1, col}
        true -> nil
      end
    end)
  end

  # The 1-indexed column of an `fn` immediately followed by a dot — `fn.(v)`,
  # `fn.field`. This is the one shape that carries its own proof: `fn` opens an
  # anonymous function and there is no syntax in which that is followed by `.`,
  # so a match here cannot be the keyword. Ledger row 164's source is exactly
  # this, one rename after its pinned `[fn | rest]`.
  defp called_fn_column(line) do
    case Regex.run(~r/\bfn(?=\.)/, line, return: :index) do
      [{col, _len}] -> col + 1
      _ -> nil
    end
  end

  # The 1-indexed column of a trailing `fn` that can only be a VALUE — the line
  # ends with it and the token before it opens a value position (`, do: fn`,
  # `x = fn`, `-> fn`, `[fn`). Anything else, notably `fn` following an
  # identifier or `)`, is left alone: `Enum.map(xs, fn` is a real keyword whose
  # clause is simply on the next line.
  @value_position_fn ~r/(?:^|[=,\[({]|->|\bdo:|\|\|)\s*fn\s*$/

  defp value_position_fn_column(line) do
    if Regex.match?(@value_position_fn, line) do
      case Regex.run(~r/\bfn\b\s*$/, line, return: :index) do
        [{col, _len}] -> col + 1
        _ -> nil
      end
    end
  end

  defp clause_follows?(lines, idx) do
    lines
    |> Enum.drop(idx + 1)
    |> Enum.find(fn {line, _shadow} -> String.trim(line) != "" end)
    |> case do
      nil -> false
      {line, _shadow} -> String.contains?(line, "->")
    end
  end

  # Return the 1-indexed column of the `fn` token in `line`.
  defp find_fn_column(line) do
    case Regex.run(~r/\bfn\b/, line, return: :index) do
      [{col, _len}] -> col + 1
      _ -> 1
    end
  end

  # Replace the `fn` token at the given 1-indexed line/column with `func`.
  # Returns `:none` unless that position really holds a standalone `fn` token,
  # so a stale or shifted column can never splice `func` into unrelated text.
  defp replace_at(source, line_no, col)
       when is_integer(line_no) and is_integer(col) and col > 0 do
    lines = String.split(source, "\n")

    case Enum.at(lines, line_no - 1) do
      nil ->
        :none

      line ->
        {before, rest} = String.split_at(line, col - 1)

        if fn_token?(before, rest) do
          new_line = before <> "func" <> String.replace_prefix(rest, "fn", "")
          {:ok, lines |> List.replace_at(line_no - 1, new_line) |> Enum.join("\n")}
        else
          :none
        end
    end
  end

  defp replace_at(_source, _line_no, _col), do: :none

  # True when `rest` starts with a whole `fn` token that `before` does not run
  # into (`:fn`, `x.fn`, `myfn` are not renameable identifiers here).
  defp fn_token?(before, rest) do
    Regex.match?(~r/^fn\b/, rest) and not Regex.match?(~r/[\w.:?!]$/u, before)
  end

  # True when `name` already appears as an identifier anywhere in the source.
  defp taken?(source, name), do: Regex.match?(~r/\b#{name}\b/, source)

  defp parses?(source), do: match?({:ok, _}, Code.string_to_quoted(source))
end
