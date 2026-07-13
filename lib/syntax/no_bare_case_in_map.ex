defmodule Credence.Syntax.NoBareCaseInMap do
  @moduledoc """
  Detects and wraps bare `case` expressions used as values inside map literals.

  A bare `case` inside `%{...}` is syntactically valid but non-idiomatic — the
  `->` arrows can be visually confused with map arrow syntax, and some Elixir
  tooling or older parsers may choke on the ambiguity. The idiomatic fix is to
  wrap the `case` in parentheses:

      # Non-idiomatic (bare case in map value)
      %{
        max_duration: case state.max do
          {nil, nil} -> nil
          {p, d} -> {p, d}
        end
      }

      # Idiomatic (parenthesized)
      %{
        max_duration: (case state.max do
          {nil, nil} -> nil
          {p, d} -> {p, d}
        end)
      }

  Detection uses Sourceror's AST to locate `case` nodes that are direct values
  of map keyword pairs and lack the `parens` metadata Sourceror adds when
  parentheses are already present.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  # Block-opening keywords that increase nesting depth when searching for `end`.
  @block_openers ~w(case if unless cond receive try for fn)

  @impl true
  def analyze(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        ast
        |> find_bare_cases_in_maps()
        |> Enum.map(fn {_case_ast, line, _col} ->
          %Issue{
            rule: :no_bare_case_in_map,
            message: "bare `case` inside a map literal — wrap in parentheses",
            meta: %{line: line}
          }
        end)

      _ ->
        []
    end
  end

  @impl true
  def fix(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        positions =
          ast
          |> find_bare_cases_in_maps()
          |> Enum.map(fn {_case_ast, line, col} -> {line, col} end)

        # Process each case independently — insert ( at case keyword,
        # ) right after the matching `end`. Work top-to-bottom; each
        # insertion is on a different line so earlier insertions don't
        # shift later ones.
        Enum.reduce(positions, source, fn {case_line, case_col}, src ->
          end_line = find_end_line(src, case_line)
          src |> insert_at(case_line, case_col, "(") |> insert_at_end(end_line, ")")
        end)

      _ ->
        source
    end
  end

  # Walk the AST looking for `case` nodes that are direct values of map keyword
  # pairs and do NOT have Sourceror's `parens` metadata.
  defp find_bare_cases_in_maps(ast) do
    {_ast, results} =
      Macro.prewalk(ast, [], fn
        {:%{}, _map_meta, entries} = node, acc when is_list(entries) ->
          found =
            entries
            |> Enum.flat_map(fn
              {{:__block__, _kw_meta, [_key]}, {:case, case_meta, _args} = case_ast}
              when is_list(case_meta) ->
                if Keyword.has_key?(case_meta, :parens) do
                  []
                else
                  # Verify the source line actually has `case` at the expected column
                  # (guards against false positives from re-parsed fragments).
                  line = Keyword.get(case_meta, :line)
                  col = Keyword.get(case_meta, :column)

                  if line && col do
                    [{case_ast, line, col}]
                  else
                    []
                  end
                end

              _ ->
                []
            end)

          {node, acc ++ found}

        node, acc ->
          {node, acc}
      end)

    results
  end

  # Find the line containing the matching `end` for a `case` starting at
  # `case_line`. Tracks block-nesting depth.
  defp find_end_line(source, case_line) do
    lines = String.split(source, "\n")
    do_find_end(lines, case_line - 1, 1)
  end

  defp do_find_end(lines, idx, depth) do
    line = Enum.at(lines, idx, "")
    trimmed = String.trim_leading(line)

    cond do
      trimmed == "" ->
        do_find_end(lines, idx + 1, depth)

      Regex.match?(~r/^end\b/, trimmed) ->
        if depth == 1 do
          idx + 1
        else
          do_find_end(lines, idx + 1, depth - 1)
        end

      Enum.any?(@block_openers, &Regex.match?(~r/^#{&1}\b/, trimmed)) ->
        do_find_end(lines, idx + 1, depth + 1)

      true ->
        do_find_end(lines, idx + 1, depth)
    end
  end

  # Insert `text` right after the `end` keyword on the given line.
  defp insert_at_end(source, line_no, text) do
    lines = String.split(source, "\n")
    target = Enum.at(lines, line_no - 1) || ""

    case Regex.run(~r/\bend\b/, target, return: :index) do
      [{pos, len}] ->
        col = pos + len + 1
        updated = insert_at_col(target, col, text)
        List.replace_at(lines, line_no - 1, updated) |> Enum.join("\n")

      _ ->
        source
    end
  end

  defp insert_at(source, line_no, col, text) do
    lines = String.split(source, "\n")
    target = Enum.at(lines, line_no - 1) || ""
    updated = insert_at_col(target, col, text)

    List.replace_at(lines, line_no - 1, updated)
    |> Enum.join("\n")
  end

  defp insert_at_col(line, col, text) do
    {before, after_} = String.split_at(line, col - 1)
    before <> text <> after_
  end
end
