defmodule Credence.Syntax.PreferListUpdateAt do
  @moduledoc """
  Detects `List.update_elem/3` (a hallucinated function) and rewrites to `List.update_at/3`.

  LLMs frequently generate `List.update_elem(list, index, value)` which does not exist
  in Elixir. The correct idiom is `List.update_at(list, index, fn _ -> value end)`.

  ## Detected patterns

      List.update_elem(list, index, value)

  ## Not flagged

      List.update_at(list, index, fn _ -> value end)    — already correct
      Enum.update_elem(list, index, value)              — different module (not our concern)
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  @update_elem_prefix "List.update_elem("

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if String.contains?(line, @update_elem_prefix) do
        [build_issue(line_no)]
      else
        []
      end
    end)
  end

  @impl true
  def fix(source) do
    case find_and_replace_update_elem(source, 0) do
      {:ok, result} -> result
      :not_found -> source
    end
  end

  # Recursively find and replace all occurrences of List.update_elem(...)
  defp find_and_replace_update_elem(source, start_pos) do
    case :binary.match(source, @update_elem_prefix, scope: {start_pos, byte_size(source) - start_pos}) do
      :nomatch ->
        :not_found

      {prefix_pos, _len} ->
        # Found an occurrence. Parse the arguments starting after "List.update_elem("
        args_start = prefix_pos + byte_size(@update_elem_prefix)
        case parse_three_args(source, args_start, byte_size(source)) do
          {:ok, arg1, arg2, arg3, args_end} ->
            # Build replacement: List.update_at(arg1, arg2, fn _ -> arg3 end)
            replacement = "List.update_at(#{arg1}, #{arg2}, fn _ -> #{arg3} end)"

            # Reconstruct the source
            before = binary_part(source, 0, prefix_pos)
            after_call = binary_part(source, args_end, byte_size(source) - args_end)
            new_source = before <> replacement <> after_call

            # Continue searching after the replacement (recursively)
            # We advance by the length of replacement from prefix_pos
            new_start = prefix_pos + byte_size(replacement)
            case find_and_replace_update_elem(new_source, new_start) do
              {:ok, result} -> {:ok, result}
              :not_found -> {:ok, new_source}
            end

          :not_found ->
            # Couldn't parse args — skip this occurrence, continue searching
            find_and_replace_update_elem(source, args_start)
        end
    end
  end

  # Parse three comma-separated arguments from source starting at `pos`, respecting
  # nested parentheses, square brackets, and braces.
  # Returns {:ok, arg1, arg2, arg3, end_pos} where end_pos is after the closing paren.
  defp parse_three_args(_source, pos, source_len) when pos >= source_len, do: :not_found

  defp parse_three_args(source, pos, source_len) do
    case collect_arg(source, pos, source_len) do
      {:ok, arg1, after_arg1} ->
        case skip_comma_and_ws(source, after_arg1, source_len) do
          {:ok, after_comma1} ->
            case collect_arg(source, after_comma1, source_len) do
              {:ok, arg2, after_arg2} ->
                case skip_comma_and_ws(source, after_arg2, source_len) do
                  {:ok, after_comma2} ->
                    case collect_arg(source, after_comma2, source_len) do
                      {:ok, arg3, after_arg3} ->
                        # After arg3 we expect a closing paren
                        case skip_ws(source, after_arg3, source_len) do
                          pos when pos < source_len ->
                            case :binary.at(source, pos) do
                              ?) -> {:ok, arg1, arg2, arg3, pos + 1}
                              _ -> :not_found
                            end
                          _ -> :not_found
                        end

                      :not_found ->
                        :not_found
                    end

                  :not_found ->
                    :not_found
                end

              :not_found ->
                :not_found
            end

          :not_found ->
            :not_found
        end

      :not_found ->
        :not_found
    end
  end

  # Collect a single argument from source, respecting balanced delimiters.
  # An argument ends at an unbalanced `)` or `,`.
  defp collect_arg(source, pos, source_len) do
    collect_arg(source, pos, source_len, pos, 0)
  end

  defp collect_arg(_source, pos, source_len, _start, _depth) when pos >= source_len,
    do: :not_found

  defp collect_arg(source, pos, source_len, start, depth) do
    char = :binary.at(source, pos)

    case char do
      ?( -> collect_arg(source, pos + 1, source_len, start, depth + 1)
      ?[ -> collect_arg(source, pos + 1, source_len, start, depth + 1)
      ?{ -> collect_arg(source, pos + 1, source_len, start, depth + 1)

      ?) when depth == 0 ->
        # End of the outer call — arg ends here
        arg = binary_part(source, start, pos - start) |> String.trim()
        {:ok, arg, pos}

      ?) ->
        collect_arg(source, pos + 1, source_len, start, depth - 1)

      ?] ->
        collect_arg(source, pos + 1, source_len, start, depth - 1)

      ?} ->
        collect_arg(source, pos + 1, source_len, start, depth - 1)

      ?, when depth == 0 ->
        # Comma separating args — arg ends here
        arg = binary_part(source, start, pos - start) |> String.trim()
        {:ok, arg, pos}

      _ ->
        collect_arg(source, pos + 1, source_len, start, depth)
    end
  end

  # Skip a comma and surrounding whitespace
  defp skip_comma_and_ws(source, pos, source_len) do
    pos = skip_ws(source, pos, source_len)

    if pos < source_len and :binary.at(source, pos) == ?, do
      {:ok, skip_ws(source, pos + 1, source_len)}
    else
      :not_found
    end
  end

  # Skip whitespace
  defp skip_ws(_source, pos, source_len) when pos >= source_len, do: pos

  defp skip_ws(source, pos, source_len) do
    case :binary.at(source, pos) do
      c when c in [?\s, ?\t, ?\n, ?\r] -> skip_ws(source, pos + 1, source_len)
      _ -> pos
    end
  end

  defp build_issue(line_no) do
    %Issue{
      rule: :prefer_list_update_at,
      message:
        "`List.update_elem/3` does not exist in Elixir. " <>
          "Use `List.update_at/3` with `fn _ -> value end` instead.",
      meta: %{line: line_no}
    }
  end
end
