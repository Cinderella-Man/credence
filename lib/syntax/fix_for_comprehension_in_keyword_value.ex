defmodule Credence.Syntax.FixForComprehensionInKeywordValue do
  @moduledoc """
  Repairs the common LLM syntax error where a bare `for` comprehension with
  keyword options (`into:`, `do:`) appears as a value inside a keyword pair
  in a container (map, keyword list, tuple), causing a parse ambiguity.

  When an LLM writes `%{foo: for x <- xs, into: %{}, do: {x, x}}`, the Elixir
  parser cannot disambiguate the container's commas from the `for` comprehension's
  keyword commas, and errors with "unexpected comma. Parentheses are required to
  solve ambiguity inside containers."

  The deterministic fix wraps the `for` comprehension in parentheses:
  `%{foo: (for x <- xs, into: %{}, do: {x, x})}`.

  ## Bad (won't parse — "unexpected comma… ambiguity inside containers")

      %{foo: for x <- [1, 2, 3], into: %{}, do: {x, x}}

  ## Good

      %{foo: (for x <- [1, 2, 3], into: %{}, do: {x, x})}
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @error_fragment "unexpected comma. Parentheses are required to solve ambiguity inside containers"

  @impl true
  def analyze(source) do
    case Code.string_to_quoted(source) do
      {:error, {meta, msg, _token}} when is_list(meta) ->
        if String.contains?(to_string(msg), @error_fragment) and
             for_in_keyword_value?(source, meta) do
          [
            %Issue{
              rule: :fix_for_comprehension_in_keyword_value,
              message: to_string(msg),
              meta: %{line: Keyword.get(meta, :line)}
            }
          ]
        else
          []
        end

      _ ->
        []
    end
  end

  @impl true
  def fix(source) do
    case Code.string_to_quoted(source) do
      {:error, {meta, msg, _token}} when is_list(meta) ->
        if String.contains?(to_string(msg), @error_fragment) and
             for_in_keyword_value?(source, meta) do
          fixed = do_fix(source, meta)
          # There may be more occurrences; recurse until stable.
          if fixed == source, do: source, else: fix(fixed)
        else
          source
        end

      _ ->
        source
    end
  end

  # Check that the error line actually contains a `for` comprehension (the
  # keyword `for` followed by `<-`), distinguishing it from an `if`/`case`/etc.
  defp for_in_keyword_value?(source, meta) do
    error_line = Keyword.get(meta, :line, 1)
    lines = String.split(source, "\n")
    line_text = Enum.at(lines, error_line - 1, "")
    # Must have `for` and `<-` on the same line to be a for comprehension
    Regex.match?(~r/\bfor\b/, line_text) and Regex.match?(~r/<-/, line_text)
  end

  defp do_fix(source, meta) do
    error_line = Keyword.get(meta, :line, 1)

    with {:ok, for_col} <- find_for_col(source, error_line),
         lines = String.split(source, "\n"),
         line_text = Enum.at(lines, error_line - 1, ""),
         chars = String.to_charlist(line_text),
         for_pos_0 = for_col - 1,
         {:ok, end_pos_0} <- find_keyword_value_end(chars, for_pos_0) do
      # Insert ")" first (higher column) then "(" so the first insert doesn't
      # shift the column of the second.
      source
      |> insert_at(error_line, end_pos_0 + 2, ")")
      |> insert_at(error_line, for_col, "(")
    else
      _ -> source
    end
  end

  # Use Sourceror to find the column of the bare `for` keyword.
  defp find_for_col(source, _error_line) do
    case Sourceror.parse_string(source) do
      {:error, {meta, _msg, _token}} ->
        col = Keyword.get(meta, :column)

        if col do
          {:ok, col}
        else
          :error
        end

      _ ->
        :error
    end
  end

  # Starting from the `for` keyword position (0-indexed), find the last keyword
  # label (`do:` or `into:`) and walk through its value. Returns the 0-indexed
  # position of the last character of the value.
  defp find_keyword_value_end(chars, for_pos_0) do
    len = length(chars)
    # Search for ALL keyword positions after the for
    into_pos = find_keyword(chars, :into, for_pos_0, len)
    do_pos = find_keyword(chars, :do, for_pos_0, len)

    # Use the last one found (do: should come after into:)
    case {do_pos, into_pos} do
      {dp, _} when is_integer(dp) ->
        # do: is last — walk its value
        end_0idx = walk_value(chars, dp + 3)
        {:ok, end_0idx}

      {_, ip} when is_integer(ip) ->
        # into: is last (no do:) — walk its value
        end_0idx = walk_value(chars, ip + 5)
        {:ok, end_0idx}

      _ ->
        :error
    end
  end

  defp find_keyword(chars, :into, from, len) do
    do_find_kw(chars, :into, from, len, nil)
  end

  defp find_keyword(chars, :do, from, len) do
    do_find_kw(chars, :do, from, len, nil)
  end

  defp do_find_kw(_chars, _kw, pos, len, found) when pos >= len, do: found

  defp do_find_kw(chars, :into = kw, pos, len, found) do
    new_found = if match_into?(chars, pos), do: pos, else: found
    do_find_kw(chars, kw, pos + 1, len, new_found)
  end

  defp do_find_kw(chars, :do = kw, pos, len, found) do
    new_found = if match_do?(chars, pos), do: pos, else: found
    do_find_kw(chars, kw, pos + 1, len, new_found)
  end

  defp match_into?(chars, pos) do
    pos + 4 < length(chars) and
      Enum.at(chars, pos) == ?i and
      Enum.at(chars, pos + 1) == ?n and
      Enum.at(chars, pos + 2) == ?t and
      Enum.at(chars, pos + 3) == ?o and
      Enum.at(chars, pos + 4) == ?: and
      (pos == 0 or not identifier_char?(Enum.at(chars, pos - 1)))
  end

  defp match_do?(chars, pos) do
    pos + 2 < length(chars) and
      Enum.at(chars, pos) == ?d and
      Enum.at(chars, pos + 1) == ?o and
      Enum.at(chars, pos + 2) == ?: and
      (pos == 0 or not identifier_char?(Enum.at(chars, pos - 1)))
  end

  defp identifier_char?(c) when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_, do: true
  defp identifier_char?(_), do: false

  # Walk forward from `pos`, skipping whitespace, then through the value
  # expression tracking ()/[]/{} depth. Returns the 0-indexed position where
  # the value ends (position of the last character of the value).
  defp walk_value(chars, pos) do
    rest = Enum.drop(chars, pos)
    ws_count = rest |> Enum.take_while(&(&1 in [?\s, ?\t])) |> length()
    start = pos + ws_count
    do_walk(Enum.drop(rest, ws_count), start, 0)
  end

  # End of string — return last position
  defp do_walk([], pos, _depth), do: pos - 1
  # Comma at depth 0 = end of value (previous character was the last)
  defp do_walk([?, | _], pos, 0), do: pos - 1
  # Closing brace/bracket/paren at depth 0 = end of value
  defp do_walk([?} | _], pos, 0), do: pos - 1
  defp do_walk([?\] | _], pos, 0), do: pos - 1
  defp do_walk([?\) | _], pos, 0), do: pos - 1
  # Newline at depth 0 = end of value
  defp do_walk([?\n | _], pos, 0), do: pos - 1
  # Track nesting
  defp do_walk([?\( | rest], pos, depth), do: do_walk(rest, pos + 1, depth + 1)
  defp do_walk([?\) | rest], pos, depth), do: do_walk(rest, pos + 1, depth - 1)
  defp do_walk([?\[ | rest], pos, depth), do: do_walk(rest, pos + 1, depth + 1)
  defp do_walk([?\] | rest], pos, depth), do: do_walk(rest, pos + 1, depth - 1)
  defp do_walk([?{ | rest], pos, depth), do: do_walk(rest, pos + 1, depth + 1)
  defp do_walk([?} | rest], pos, depth), do: do_walk(rest, pos + 1, depth - 1)
  # Any other character
  defp do_walk([_ | rest], pos, depth), do: do_walk(rest, pos + 1, depth)

  # Insert `text` at the given 1-indexed line and 1-indexed column.
  defp insert_at(source, line_no, col, text) do
    lines = String.split(source, "\n")
    target = Enum.at(lines, line_no - 1) || ""
    {before, after_} = String.split_at(target, col - 1)
    updated = before <> text <> after_

    List.replace_at(lines, line_no - 1, updated)
    |> Enum.join("\n")
  end
end
