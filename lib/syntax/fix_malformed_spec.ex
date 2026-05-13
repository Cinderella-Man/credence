defmodule Credence.Syntax.FixMalformedSpec do
  @moduledoc """
  Fixes `@spec` declarations where the `::` return type separator is
  misplaced inside the argument parentheses.

  LLMs translating from Python sometimes put the entire spec — parameter
  types AND return type — inside one pair of parentheses, placing `::` in
  the wrong position.

  ## Bad (won't parse)

      @spec max_product(list(integer()) :: integer())

  ## Good

      @spec max_product(list(integer())) :: integer()

  ## Detection

  Finds `@spec` lines where the matching `)` for the opening `(` is the
  LAST `)` on the line and the `::` separator sits inside those parens
  rather than outside. Valid specs with named parameters (`name :: type`)
  are not flagged because they always have a `::` outside the argument
  parens as well.
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if malformed_spec?(line), do: [build_issue(line_no)], else: []
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.map(&fix_line/1)
    |> Enum.join("\n")
  end

  # ── Detection ──────────────────────────────────────────────────

  defp malformed_spec?(line) do
    case extract_spec_parts(line) do
      {:ok, _prefix, inner, after_close} ->
        # Malformed if :: is inside the parens but NOT outside
        not String.contains?(after_close, "::") and
          find_last_separator(inner) != nil

      :skip ->
        false
    end
  end

  # ── Fix ────────────────────────────────────────────────────────

  defp fix_line(line) do
    case extract_spec_parts(line) do
      {:ok, prefix, inner, after_close} ->
        if not String.contains?(after_close, "::") do
          case find_last_separator(inner) do
            nil ->
              line

            pos ->
              {params_part, "::" <> return_part} = String.split_at(inner, pos)
              params = String.trim_trailing(params_part)
              return_type = String.trim_leading(return_part)
              "#{prefix}(#{params}) :: #{return_type}"
          end
        else
          line
        end

      :skip ->
        line
    end
  end

  # ── Shared parsing ─────────────────────────────────────────────

  # Extracts the prefix (@spec func_name), the content between the
  # outermost parens, and whatever follows the matching close paren.
  defp extract_spec_parts(line) do
    case Regex.run(~r/^(\s*@spec\s+\w+[?!]?)\(/, line) do
      [full_match, prefix] ->
        rest = String.slice(line, String.length(full_match), String.length(line))

        case find_matching_close(String.to_charlist(rest)) do
          {:ok, inner, after_close} -> {:ok, prefix, inner, after_close}
          :unbalanced -> :skip
        end

      nil ->
        :skip
    end
  end

  # Finds the matching ) for an already-opened ( (depth starts at 1).
  # Returns {:ok, inner_content, text_after_close} or :unbalanced.
  defp find_matching_close(chars), do: do_close(chars, 1, [])

  defp do_close([], _depth, _acc), do: :unbalanced
  defp do_close([?) | rest], 1, acc) do
    inner = acc |> Enum.reverse() |> List.to_string()
    {:ok, inner, List.to_string(rest)}
  end
  defp do_close([?) | rest], depth, acc), do: do_close(rest, depth - 1, [?) | acc])
  defp do_close([?( | rest], depth, acc), do: do_close(rest, depth + 1, [?( | acc])
  defp do_close([c | rest], depth, acc), do: do_close(rest, depth, [c | acc])

  # ── Separator finding ──────────────────────────────────────────

  # Finds the character position of the LAST :: at paren depth 0
  # within the content string. Returns nil if none found.
  defp find_last_separator(content) do
    content |> String.to_charlist() |> do_sep(0, 0, nil)
  end

  defp do_sep([], _pos, _depth, last), do: last
  defp do_sep([?( | rest], pos, depth, last), do: do_sep(rest, pos + 1, depth + 1, last)
  defp do_sep([?) | rest], pos, depth, last), do: do_sep(rest, pos + 1, depth - 1, last)
  defp do_sep([?:, ?: | rest], pos, 0, _last), do: do_sep(rest, pos + 2, 0, pos)
  defp do_sep([_ | rest], pos, depth, last), do: do_sep(rest, pos + 1, depth, last)

  # ── Issue ──────────────────────────────────────────────────────

  defp build_issue(line_no) do
    %Issue{
      rule: :malformed_spec,
      message:
        "The `::` return type separator is inside the argument parens. " <>
          "Move `)` before `::` — e.g. `@spec func(type) :: return`.",
      meta: %{line: line_no}
    }
  end
end
