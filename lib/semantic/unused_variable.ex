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

  ## Name collisions

  A plain `_` prefix is not always behaviour-preserving. In

      def f({_ref, ref}), do: :ok

  rewriting `ref` to `_ref` would produce `{_ref, _ref}`, and an
  underscored name repeated in a pattern still *binds*: the clause then
  only matches when both elements are equal (`f({1, 2})` stops matching).
  So when `_<var_name>` already occurs in the source as a standalone
  identifier, the fix picks the first free `_<var_name>_<n>` instead.
  Renaming is safe precisely because the binding is unused — nothing
  reads it.

  The converse warning — *"the underscored variable `_x` appears more
  than once in a match"* — is deliberately **not** handled. The compiler
  itself says the two repairs are "remove the leading underscore"
  (keeps the equality constraint) or "give the variables different
  names" (drops it), and only the first preserves the answer; picking
  either automatically would be guessing at intent.

  ## Bad

      defmodule UnusedVarInteg1UV do
        def run do
          {current, max} = {1, 2}
          max
        end
      end

  ## Good

      defmodule UnusedVarInteg1UV do
        def run do
          {_current, max} = {1, 2}
          max
        end
      end
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
        new_name = unique_underscore_name(source, var_name)
        replace_token_at(line, offset, var_name, new_name)
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
        [single] ->
          new_name = unique_underscore_name(source, var_name)
          replace_token_at(line, single, var_name, new_name)

        _ ->
          line
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

  # Build a unique underscore-prefixed name that doesn't collide with
  # existing bindings, including bindings on another line of the same pattern.
  defp unique_underscore_name(source, var_name) do
    target = "_" <> var_name

    if has_standalone_occurrence?(source, target) do
      next_available_name(source, var_name, 1)
    else
      target
    end
  end

  defp next_available_name(source, base, n) do
    candidate = "_#{base}_#{n}"

    if has_standalone_occurrence?(source, candidate) do
      next_available_name(source, base, n + 1)
    else
      candidate
    end
  end

  defp has_standalone_occurrence?(line, name) do
    standalone_offsets(line, name) != []
  end

  defp replace_token_at(line, offset, old_name, new_name) do
    prefix = binary_part(line, 0, offset)
    suffix_start = offset + byte_size(old_name)
    suffix = binary_part(line, suffix_start, byte_size(line) - suffix_start)
    prefix <> new_name <> suffix
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
