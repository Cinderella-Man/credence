defmodule Credence.Syntax.PreferSpecArrowOperator do
  @moduledoc """
  Fixes `@spec` declarations where the `::` arrow operator is missing
  before the return type.

  LLMs repeatedly generate `@spec fn(args) return_type()` missing the
  `::` arrow before the return type — a syntax parse failure.

  ## Bad (won't parse)

      @spec get_days_between_dates(String.t(), String.t()) integer()

  ## Good

      @spec get_days_between_dates(String.t(), String.t()) :: integer()

  ## Detection

  Finds `@spec` lines where the matching `)` for the opening `(` is
  followed by a type expression but no `::` separator. Lines with a
  guard clause (`when ...`) are not flagged — the missing-arrow after
  a guard is a different, more complex fault.
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if missing_arrow?(line), do: [build_issue(line_no)], else: []
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.map_join("\n", &fix_line/1)
  end

  defp missing_arrow?(line) do
    case extract_spec_parts(line) do
      {:ok, _prefix, _inner, after_close} ->
        trimmed = String.trim_leading(after_close)

        not String.contains?(after_close, "::") and
          trimmed != "" and
          starts_with_type?(trimmed) and
          not starts_with_guard?(trimmed)

      :skip ->
        false
    end
  end

  defp fix_line(line) do
    case extract_spec_parts(line) do
      {:ok, prefix, inner, after_close} ->
        if String.contains?(after_close, "::") do
          line
        else
          trimmed = String.trim_leading(after_close)

          if trimmed != "" and starts_with_type?(trimmed) and
               not starts_with_guard?(trimmed) do
            "#{prefix}(#{inner}) :: #{trimmed}"
          else
            line
          end
        end

      :skip ->
        line
    end
  end

  # A type expression starts with an uppercase letter (Module.type),
  # lowercase letter (type), { (tuple), [ (list), % (map/struct),
  # or : (atom literal). Guards starting with `when` are excluded.
  defp starts_with_type?(str) do
    Regex.match?(~r/^(?!when\b)[A-Za-z_{%\[:]/, str)
  end

  defp starts_with_guard?(str) do
    Regex.match?(~r/^when\b/, str)
  end

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

  defp build_issue(line_no) do
    %Issue{
      rule: :prefer_spec_arrow_operator,
      message:
        "Missing `::` before return type in @spec. " <>
          "Add `::` before the return type — e.g. `@spec func(type) :: return`.",
      meta: %{line: line_no}
    }
  end
end
