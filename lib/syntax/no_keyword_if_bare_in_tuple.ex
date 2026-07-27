defmodule Credence.Syntax.NoKeywordIfBareInTuple do
  @moduledoc """
  Repairs the common LLM syntax error where a keyword-syntax `if`/`unless`
  appears bare inside tuple braces, causing a parse ambiguity.

  When an LLM writes `{:ok, if num < 1, do: 1, else: num}`, the Elixir parser
  cannot disambiguate the tuple separator commas from the keyword-syntax commas,
  and errors with "unexpected comma. Parentheses are required to solve ambiguity
  inside containers."

  The deterministic fix wraps the keyword-syntax expression in parentheses:
  `{:ok, (if num < 1, do: 1, else: num)}`.

  ## Bad (won't parse — "unexpected comma… ambiguity inside containers")

      {:ok, if num < 1, do: 1, else: num}

  ## Good

      {:ok, (if num < 1, do: 1, else: num)}
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @error_fragment "unexpected comma. Parentheses are required to solve ambiguity inside containers"

  @impl true
  def analyze(source) do
    case Code.string_to_quoted(source) do
      {:error, {meta, msg, _token}} when is_list(meta) ->
        if String.contains?(to_string(msg), @error_fragment) do
          [
            %Issue{
              rule: :no_keyword_if_bare_in_tuple,
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
        if String.contains?(to_string(msg), @error_fragment) do
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

  defp do_fix(source, meta) do
    error_line = Keyword.get(meta, :line, 1)

    # Sourceror gives us the column of the ambiguous `if` keyword
    with {:ok, if_col} <- find_if_col(source, error_line),
         lines = String.split(source, "\n"),
         line_text = Enum.at(lines, error_line - 1, ""),
         chars = String.to_charlist(line_text),
         # 0-indexed position of the `if` keyword
         if_pos_0 = if_col - 1,
         # Find the last keyword label (else: or do:) after the if, then walk
         # through its value to find where to insert the closing paren.
         {:ok, end_pos_0} <- find_last_keyword_value_end(chars, if_pos_0) do
      # Insert ")" first (higher column) then "(" so the first insert doesn't
      # shift the column of the second.
      source
      |> insert_at(error_line, end_pos_0 + 2, ")")
      |> insert_at(error_line, if_col, "(")
    else
      _ -> source
    end
  end

  # Use Sourceror to find the column of the bare `if` keyword.
  # Sourceror's error column points to the `if` keyword itself.
  defp find_if_col(source, _error_line) do
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

  # Starting from the `if` keyword position (0-indexed), find the last keyword
  # label (`else:` or `do:`) and walk through its value. Returns the 0-indexed
  # position of the last character of the value.
  defp find_last_keyword_value_end(chars, if_pos_0) do
    len = length(chars)
    # Search for ALL keyword positions after the if
    do_pos = find_keyword(chars, :do, if_pos_0, len)
    else_pos = find_keyword(chars, :else, if_pos_0, len)

    # Use the last one found
    case {do_pos, else_pos} do
      {_, ep} when is_integer(ep) ->
        # else: is last — walk its value
        end_0idx = walk_value(chars, ep + 5)
        {:ok, end_0idx}

      {dp, _} when is_integer(dp) ->
        # do: is last (no else:) — walk its value
        end_0idx = walk_value(chars, dp + 3)
        {:ok, end_0idx}

      _ ->
        :error
    end
  end

  # Find the 0-indexed position of a keyword label (`:do` or `:else`) in chars,
  # searching forward from `from`. Returns position or nil.
  defp find_keyword(chars, :else, from, len) do
    do_find_kw(chars, :else, from, len, nil)
  end

  defp find_keyword(chars, :do, from, len) do
    do_find_kw(chars, :do, from, len, nil)
  end

  defp do_find_kw(_chars, _kw, pos, len, found) when pos >= len, do: found

  defp do_find_kw(chars, :else = kw, pos, len, found) do
    new_found = if match_else?(chars, pos), do: pos, else: found
    do_find_kw(chars, kw, pos + 1, len, new_found)
  end

  defp do_find_kw(chars, :do = kw, pos, len, found) do
    new_found = if match_do?(chars, pos), do: pos, else: found
    do_find_kw(chars, kw, pos + 1, len, new_found)
  end

  defp match_else?(chars, pos) do
    pos + 4 < length(chars) and
      Enum.at(chars, pos) == ?e and
      Enum.at(chars, pos + 1) == ?l and
      Enum.at(chars, pos + 2) == ?s and
      Enum.at(chars, pos + 3) == ?e and
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
