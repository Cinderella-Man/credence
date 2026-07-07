defmodule Credence.Syntax.NoFnAsVariable do
  @moduledoc """
  Repairs the common LLM syntax error where `fn` is used as a variable name
  instead of a proper identifier like `func`.

  Since `fn` is a reserved keyword in Elixir (used for anonymous functions),
  using it as a variable name causes `MismatchedDelimiterError` or
  "missing terminator: end" errors. The parser treats `fn` as the start of
  an anonymous function and expects `end`, but finds `]`, `}`, or end-of-input
  instead.

  The deterministic fix renames `fn` → `func` wherever it appears as an
  identifier in a non-keyword position.

  ## Bad (won't parse — MismatchedDelimiterError)

      def foo([fn | rest]), do: fn

  ## Good

      def foo([func | rest]), do: func
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

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

  # Shared logic: try to fix, commit only when the result actually parses.
  defp repair(source) do
    fixed = do_fix(source, 0)

    if fixed != source and parses?(fixed) do
      {:fixed, fixed, first_error_line(source)}
    else
      :no_fix
    end
  end

  # Iteratively replace `fn` → `func` at the position the parser reports,
  # one token per pass, until the code parses or we exhaust the budget.
  defp do_fix(source, pass) when pass < @max_passes do
    case Code.string_to_quoted(source, columns: true) do
      {:ok, _} ->
        source

      {:error, {meta, _msg, _token}} when is_list(meta) ->
        case find_fix_position(source, meta) do
          {:ok, line, col} ->
            fixed = replace_at(source, line, col)
            do_fix(fixed, pass + 1)

          :none ->
            source
        end

      _ ->
        source
    end
  end

  defp do_fix(source, _pass), do: source

  # Determine where a `fn` → `func` replacement should happen based on the
  # parser error metadata. Returns `{:ok, line, col}` or `:none`.
  defp find_fix_position(source, meta) do
    cond do
      # fn mismatched with ] or } — fn used as variable in list/tuple pattern
      Keyword.get(meta, :error_type) == :mismatched_delimiter and
          Keyword.get(meta, :opening_delimiter) == :fn and
          Keyword.get(meta, :closing_delimiter) in [:"]", :"}"] ->
        {:ok, Keyword.get(meta, :line), Keyword.get(meta, :column)}

      # fn with missing terminator — fn used as standalone variable
      # (e.g. `fn = 1`, `fn` at end of expression). Excludes the
      # NoUnclosedFnDelimiter case (closing_delimiter: :")") which is
      # handled by that rule.
      Keyword.get(meta, :opening_delimiter) == :fn and
          Keyword.get(meta, :expected_delimiter) == :end ->
        {:ok, Keyword.get(meta, :line), Keyword.get(meta, :column)}

      # do block missing its `end` — the parser consumed the `end` for a
      # stray `fn` keyword (which is actually a variable reference).
      # Look for a standalone `fn` on its own line.
      Keyword.get(meta, :opening_delimiter) == :do and
          Keyword.get(meta, :expected_delimiter) == :end ->
        find_standalone_fn(source)

      true ->
        :none
    end
  end

  # Find a line that is nothing but `fn` (with optional whitespace) —
  # a standalone variable reference the parser misinterpreted as the keyword.
  defp find_standalone_fn(source) do
    lines = String.split(source, "\n")

    case Enum.find_index(lines, &(String.trim(&1) == "fn")) do
      nil ->
        :none

      idx ->
        line = Enum.at(lines, idx)
        col = find_fn_column(line)
        {:ok, idx + 1, col}
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
  defp replace_at(source, line_no, col) do
    lines = String.split(source, "\n")
    line = Enum.at(lines, line_no - 1)
    pos = col - 1
    {before, rest} = String.split_at(line, pos)
    new_line = before <> "func" <> String.replace_prefix(rest, "fn", "")
    List.replace_at(lines, line_no - 1, new_line) |> Enum.join("\n")
  end

  # Return the line number from the first parser error (for issue metadata).
  defp first_error_line(source) do
    case Code.string_to_quoted(source, columns: true) do
      {:error, {meta, _msg, _token}} when is_list(meta) ->
        Keyword.get(meta, :line, 1)

      _ ->
        1
    end
  end

  defp parses?(source), do: match?({:ok, _}, Code.string_to_quoted(source))
end
