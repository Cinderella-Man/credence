defmodule Credence.Semantic.FixInvalidListTypespecSyntax do
  @moduledoc """
  Fixes invalid `list([...])` typespec syntax in @spec attributes.

  LLMs frequently write `list([a, b])` in @spec, but `list/1` is not a valid
  typespec form — it is a function call, not a type constructor. The Elixir
  compiler emits:

      unexpected list in typespec: [...]

  The fix replaces `list([a, b])` with `[[a, b]]` on the flagged line.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, "unexpected list in typespec")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_invalid_list_typespec_syntax,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    line_no = line(diagnostic)

    if line_no do
      source
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn
        {text, ^line_no} -> replace_list_typespec(text)
        {text, _} -> text
      end)
    else
      source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
  defp line(_), do: nil

  # Replace all `list([...])` occurrences on a single line with `[[...]]`.
  defp replace_list_typespec(line) do
    case find_list_typespec(line) do
      nil ->
        line

      {full_start, full_end, inner_start, inner_end} ->
        before = binary_part(line, 0, full_start)
        inner = binary_part(line, inner_start, inner_end - inner_start)
        after_ = binary_part(line, full_end, byte_size(line) - full_end)
        # list([X]) → [[X]] — the inner content between `list([` and `])` is X
        replaced = before <> "[[" <> inner <> "]]" <> after_
        # Recurse to handle multiple list([...]) on the same line
        replace_list_typespec(replaced)
    end
  end

  # Find a `list([...])` pattern in the line, returning
  # {full_start, full_end, inner_start, inner_end} byte ranges.
  defp find_list_typespec(line) do
    case :binary.match(line, "list([") do
      :nomatch ->
        nil

      {start, _len} ->
        inner_start = start + 6

        case find_matching_close(line, inner_start) do
          nil ->
            nil

          close_pos ->
            # close_pos is the byte offset of ']' in '])'
            full_end = close_pos + 2
            {start, full_end, inner_start, close_pos}
        end
    end
  end

  # Scan for the closing `])` of a `list([...])` pattern, tracking bracket depth.
  # `pos` starts right after the opening `[` of the inner list.
  defp find_matching_close(line, pos), do: do_find_close(line, pos, 0)

  defp do_find_close(line, pos, _depth) when pos >= byte_size(line), do: nil

  defp do_find_close(line, pos, depth) do
    <<_::binary-size(^pos), char::binary-1, _::binary>> = line

    case char do
      "[" ->
        do_find_close(line, pos + 1, depth + 1)

      "]" ->
        if depth == 0 do
          # This is the closing ']' — check if followed by ')'
          next_pos = pos + 1

          if next_pos < byte_size(line) do
            <<_::binary-size(^next_pos), next_char::binary-1, _::binary>> = line

            if next_char == ")" do
              pos
            else
              do_find_close(line, pos + 1, 0)
            end
          else
            do_find_close(line, pos + 1, 0)
          end
        else
          do_find_close(line, pos + 1, depth - 1)
        end

      _ ->
        do_find_close(line, pos + 1, depth)
    end
  end
end
