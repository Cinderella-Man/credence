defmodule Credence.Syntax.NoKeywordIfInTuple do
  @moduledoc """
  Repairs the common LLM syntax error where a keyword-syntax `if`/`case`/`cond`
  appears inside a tuple with trailing elements, causing a parse error.

  When an LLM writes `{if expr, do: val, else: val2, other}`, the Elixir parser
  interprets `do:`/`else:` as a keyword list and then chokes on the trailing
  tuple elements ("unexpected expression after keyword list").

  The deterministic fix wraps the keyword-syntax expression in parentheses:
  `{(if expr, do: val, else: val2), other}`.

  ## Bad (won't parse — "unexpected expression after keyword list")

      {if direction == :asc, do: product.score, else: -product.score, product.name}

  ## Good

      {(if direction == :asc, do: product.score, else: -product.score), product.name}
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @error_fragment "unexpected expression after keyword list"

  @impl true
  def analyze(source) do
    case Code.string_to_quoted(source) do
      {:error, {meta, msg, _token}} when is_list(meta) ->
        if String.contains?(to_string(msg), @error_fragment) do
          [
            %Issue{
              rule: :no_keyword_if_in_tuple,
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
          do_fix(source, meta)
        else
          source
        end

      _ ->
        source
    end
  end

  defp do_fix(source, meta) do
    error_line = Keyword.get(meta, :line, 1)
    error_col = Keyword.get(meta, :column, 1)
    lines = String.split(source, "\n")
    error_line_text = Enum.at(lines, error_line - 1) || ""

    with {:ok, insert_paren_col} <- find_close_paren_pos(error_line_text, error_col),
         {:ok, if_line, if_col} <- find_if_keyword(lines, error_line) do
      source
      |> insert_at(error_line, insert_paren_col, ")")
      |> insert_at(if_line, if_col, "(")
    else
      _ -> source
    end
  end

  # Find the 1-indexed column where ")" should be inserted on the error line.
  # Strategy: search backward from the error position for the last keyword label
  # (else: or do:), then walk forward through its value to find where it ends.
  defp find_close_paren_pos(line, error_col) do
    chars = String.to_charlist(line)
    # error_col is 1-indexed; search from the character before the error position
    search_from = error_col - 2

    case find_last_keyword(chars, search_from) do
      {:else, pos} ->
        # pos is 0-indexed position of 'e' in 'else:'
        # Value starts after "else:" + optional whitespace
        end_0idx = walk_value(chars, pos + 5)
        {:ok, end_0idx + 1}

      {:do, pos} ->
        # pos is 0-indexed position of 'd' in 'do:'
        end_0idx = walk_value(chars, pos + 3)
        {:ok, end_0idx + 1}

      :not_found ->
        :error
    end
  end

  # Search backward from position `from` for "else:" or "do:" label.
  # Returns {:else, pos} | {:do, pos} | :not_found
  defp find_last_keyword(chars, from) do
    find_last_kw(chars, from, nil)
  end

  defp find_last_kw(_chars, pos, found) when pos < 0, do: found

  defp find_last_kw(chars, pos, found) do
    cond do
      pos >= 4 and match_else?(chars, pos) ->
        # Found the rightmost keyword — return immediately
        {:else, pos - 4}

      pos >= 2 and match_do?(chars, pos) ->
        {:do, pos - 2}

      true ->
        find_last_kw(chars, pos - 1, found)
    end
  end

  defp match_else?(chars, pos) do
    Enum.at(chars, pos) == ?: and
      Enum.at(chars, pos - 1) == ?e and
      Enum.at(chars, pos - 2) == ?s and
      Enum.at(chars, pos - 3) == ?l and
      Enum.at(chars, pos - 4) == ?e and
      # Ensure it's not part of a longer identifier
      (pos - 5 < 0 or not identifier_char?(Enum.at(chars, pos - 5)))
  end

  defp match_do?(chars, pos) do
    Enum.at(chars, pos) == ?: and
      Enum.at(chars, pos - 1) == ?o and
      Enum.at(chars, pos - 2) == ?d and
      # Ensure it's not part of a longer identifier (e.g. "undo:")
      (pos - 3 < 0 or not identifier_char?(Enum.at(chars, pos - 3)))
  end

  defp identifier_char?(c) when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_, do: true
  defp identifier_char?(_), do: false

  # Walk forward from `pos`, skipping whitespace, then through the value expression
  # tracking ()/[]/{} depth. Returns the 0-indexed position where the value ends
  # (i.e., the position of the next comma/brace/newline at depth 0).
  defp walk_value(chars, pos) do
    # Skip whitespace after the colon
    rest = Enum.drop(chars, pos)
    ws_count = rest |> Enum.take_while(&(&1 in [?\s, ?\t])) |> length()
    start = pos + ws_count
    do_walk(Enum.drop(rest, ws_count), start, 0)
  end

  # End of string
  defp do_walk([], pos, _depth), do: pos
  # Comma at depth 0 = end of value (next tuple element)
  defp do_walk([?, | _], pos, 0), do: pos
  # Closing brace/bracket/paren at depth 0 = end of value
  defp do_walk([?} | _], pos, 0), do: pos
  defp do_walk([?\] | _], pos, 0), do: pos
  defp do_walk([?\) | _], pos, 0), do: pos
  # Newline at depth 0 = end of value (continuation on next line is a new tuple element)
  defp do_walk([?\n | _], pos, 0), do: pos
  # Track nesting
  defp do_walk([?\( | rest], pos, depth), do: do_walk(rest, pos + 1, depth + 1)
  defp do_walk([?\) | rest], pos, depth), do: do_walk(rest, pos + 1, depth - 1)
  defp do_walk([?\[ | rest], pos, depth), do: do_walk(rest, pos + 1, depth + 1)
  defp do_walk([?\] | rest], pos, depth), do: do_walk(rest, pos + 1, depth - 1)
  defp do_walk([?{ | rest], pos, depth), do: do_walk(rest, pos + 1, depth + 1)
  defp do_walk([?} | rest], pos, depth), do: do_walk(rest, pos + 1, depth - 1)
  # Any other character
  defp do_walk([_ | rest], pos, depth), do: do_walk(rest, pos + 1, depth)

  # Search backward from `error_line` for a line containing an unparenthesized
  # if/case/cond/unless keyword.
  defp find_if_keyword(lines, error_line) do
    Enum.reduce_while((error_line - 1)..0//-1, :error, fn idx, _acc ->
      line = Enum.at(lines, idx) || ""

      case Regex.run(~r/\b(if|case|cond|unless)\b/, line, return: :index) do
        [{col, _len} | _] ->
          {:halt, {:ok, idx + 1, col + 1}}

        nil ->
          {:cont, :error}
      end
    end)
  end

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
