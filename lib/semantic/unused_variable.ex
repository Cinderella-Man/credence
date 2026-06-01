defmodule Credence.Semantic.UnusedVariable do
  @moduledoc """
  Fixes compiler warnings about unused variables by adding `_` prefix.

  LLMs often generate destructuring patterns where not all bound variables
  are used, causing `--warnings-as-errors` to fail compilation.

  ## Example

      # Warning: variable "current_sum" is unused
      {current_sum, max_sum} = Enum.reduce(...)

      # Fixed:
      {_current_sum, max_sum} = Enum.reduce(...)

  ## How the fix locates the binding

  The compiler diagnostic carries a `{line, col}` position pointing at
  the *first character* of the unused binding (1-indexed). The fix
  uses that column strictly:

    * if `var_name` lives at that exact column with non-word characters
      on both sides, insert `_` there;
    * otherwise refuse to act — silently mangling the wrong identifier
      is far worse than leaving the warning visible.

  When the diagnostic carries only a line (no column), the fix falls
  back to "rewrite only if `var_name` appears exactly once on the line
  as a standalone identifier" — same safety principle.
  """
  use Credence.Semantic.Rule
  alias Credence.Issue

  @impl true
  def match?(%{severity: :warning, message: msg}) do
    String.match?(msg, ~r/variable ".*" is unused/)
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :unused_variable,
      message: msg,
      meta: %{line: extract_line(position)}
    }
  end

  @impl true
  def fix(source, %{message: msg, position: position}) do
    case extract_variable_name(msg) do
      nil -> source
      "_" <> _ -> source
      var_name -> apply_underscore(source, var_name, position)
    end
  end

  defp extract_line({line, _col}) when is_integer(line), do: line
  defp extract_line(line) when is_integer(line), do: line
  defp extract_line(_), do: nil

  defp extract_variable_name(msg) do
    case Regex.run(~r/variable "([^"]+)" is unused/, msg) do
      [_, name] -> name
      _ -> nil
    end
  end

  # Precise column → strict insert at the exact byte offset.
  defp apply_underscore(source, var_name, {line_no, col})
       when is_integer(line_no) and is_integer(col) do
    rewrite_line(source, line_no, fn line ->
      offset = col - 1

      if at_standalone_token?(line, offset, var_name) do
        insert_underscore_at(line, offset, var_name)
      else
        line
      end
    end)
  end

  # Position with a non-integer column → treat as line-only.
  defp apply_underscore(source, var_name, {line_no, _}) when is_integer(line_no),
    do: rewrite_unambiguous(source, line_no, var_name)

  # Bare integer position → fall back to unambiguous rewrite.
  defp apply_underscore(source, var_name, line_no) when is_integer(line_no),
    do: rewrite_unambiguous(source, line_no, var_name)

  defp apply_underscore(source, _var_name, _position), do: source

  # Insert `_` only if `var_name` appears exactly once on the line as
  # a standalone identifier — protects against the bug class where
  # the var name is also a substring of a string key, atom key, or
  # function name on the same line.
  defp rewrite_unambiguous(source, line_no, var_name) do
    rewrite_line(source, line_no, fn line ->
      case standalone_offsets(line, var_name) do
        [single] -> insert_underscore_at(line, single, var_name)
        _ -> line
      end
    end)
  end

  defp rewrite_line(source, line_no, fun) when is_integer(line_no) and line_no >= 1 do
    lines = String.split(source, "\n")

    case Enum.at(lines, line_no - 1) do
      nil ->
        source

      line ->
        case fun.(line) do
          ^line ->
            source

          new_line ->
            lines
            |> List.replace_at(line_no - 1, new_line)
            |> Enum.join("\n")
        end
    end
  end

  defp rewrite_line(source, _, _), do: source

  defp at_standalone_token?(line, offset, name) do
    name_size = byte_size(name)

    offset >= 0 and
      offset + name_size <= byte_size(line) and
      binary_part(line, offset, name_size) == name and
      not preceded_by_word_char?(line, offset) and
      not followed_by_word_char?(line, offset + name_size)
  end

  # Insert `_` before the token at `offset`.  When `var_name` is given,
  # checks whether `_varname` already exists elsewhere on the line; if
  # so, replaces the token with bare `_` instead (avoids "underscored
  # variable appears more than once" warnings).
  defp insert_underscore_at(line, offset, var_name) do
    underscored = "_" <> var_name

    if already_has_underscored?(line, offset, underscored) do
      # Replace the token with `_` instead of prepending `_`
      prefix = binary_part(line, 0, offset)

      suffix =
        binary_part(line, offset + byte_size(var_name), byte_size(line) - offset - byte_size(var_name))

      prefix <> "_" <> suffix
    else
      prefix = binary_part(line, 0, offset)
      suffix = binary_part(line, offset, byte_size(line) - offset)
      prefix <> "_" <> suffix
    end
  end

  # Returns true if `underscored` (e.g. `_last`) already exists as a
  # standalone token on the line at a position OTHER than `offset`
  # (where the un-prefixed variable currently sits).
  defp already_has_underscored?(line, offset, underscored) do
    underscored_size = byte_size(underscored)

    # Walk through the line looking for standalone occurrences of `_name`
    # that are NOT at `offset` (where `name` currently sits, which will
    # become `_name` after the fix).
    Stream.iterate(0, &(&1 + 1))
    |> Stream.take_while(&(&1 <= byte_size(line) - underscored_size))
    |> Enum.any?(fn pos ->
      binary_part(line, pos, underscored_size) == underscored and
        not preceded_by_word_char?(line, pos) and
        not followed_by_word_char?(line, pos + underscored_size) and
        # Skip the position where `name` currently lives — that's the
        # one we're about to change, so it doesn't count as "already
        # existing."
        pos != offset
    end)
  end

  defp preceded_by_word_char?(_line, 0), do: false

  defp preceded_by_word_char?(line, offset),
    do: word_char?(binary_part(line, offset - 1, 1))

  defp followed_by_word_char?(line, offset) do
    if offset < byte_size(line),
      do: word_char?(binary_part(line, offset, 1)),
      else: false
  end

  defp word_char?(<<c>>) when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_, do: true
  defp word_char?(_), do: false

  defp standalone_offsets(line, name) do
    ~r/\b#{Regex.escape(name)}\b/
    |> Regex.scan(line, return: :index)
    |> Enum.map(fn [{offset, _}] -> offset end)
  end
end
