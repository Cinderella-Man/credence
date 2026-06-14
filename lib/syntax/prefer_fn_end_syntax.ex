defmodule Credence.Syntax.PreferFnEndSyntax do
  @moduledoc """
  Detects Python-style lambda syntax and wraps with `fn ... end`.

  LLMs generating Elixir code from Python sometimes produce:

      acc -> acc * n

  instead of the correct Elixir syntax:

      fn acc, _i -> acc * n end

  The bare `->` outside `fn ... end` is a parse failure. This rule
  detects lines containing `->` that are not wrapped in `fn ... end`
  and repairs them.

  ## Detected patterns

      acc -> acc * n
      x, acc -> x + acc
      val -> val * 2

  ## Not flagged

      fn x -> x + 1 end        — already correct
      case x do y -> y end     — case/receive/cond/try arrows
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  # Pattern to match lambda parameters before ->
  # Matches: ident -> or ident, ident ->
  # Does NOT match things like 1..n where n would be falsely captured
  @lambda_params_pattern ~r/\b([a-z_]\w*(?:\s*,\s*[a-z_]\w*)*)\s*->/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if has_bare_arrow?(line), do: [build_issue(line_no)], else: []
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      if has_bare_arrow?(line), do: fix_line(line), else: line
    end)
  end

  defp has_bare_arrow?(line) do
    # Must have an arrow
    has_arrow = Regex.match?(~r/->/, line)
    # Must not already have fn
    has_fn = Regex.match?(~r/\bfn\b/, line)
    # Must not be a comment
    is_comment = Regex.match?(~r/^\s*#/, line)
    # Must not be part of case/receive/cond/try/do block clause
    # These typically look like:  pattern -> body
    # where the line starts with whitespace and just a pattern before ->
    is_case_clause = case_clause_line?(line)

    has_arrow and not has_fn and not is_comment and not is_case_clause
  end

  defp case_clause_line?(line) do
    # A case/receive/cond/try clause typically starts with whitespace
    # followed by a simple pattern (identifier, literal, or _) then ->
    # Examples:  y -> body
    #            _ -> body
    #            :ok -> body
    #            {x, y} -> body
    # Or it's on the same line as case/receive/cond/try/do: case x do y -> y end
    # We check if the line starts with just whitespace + pattern + ->
    # (i.e., no other content before the pattern)
    starts_with_pattern = Regex.match?(~r/^\s*[a-z_A-Z:][_a-zA-Z0-9]*\s*->/, line)
    has_comma = Regex.match?(~r/^\s*[a-z_]\w*\s*,/, line)
    # Also check if line contains case/receive/cond/try ... do ... ->
    has_case_context = Regex.match?(~r/\b(case|receive|cond|try|fn)\b.*\bdo\b.*->/, line)
    # Check if the char before -> (ignoring whitespace) is not a letter/underscore.
    # This catches clause expressions like: value > 3 ->, {x, y} ->, is_atom(x) ->
    # Lambda params always end with an identifier char (letter/underscore).
    non_identifier_before_arrow? = non_identifier_before_arrow?(line)

    (starts_with_pattern and not has_comma) or has_case_context or non_identifier_before_arrow?
  end

  defp non_identifier_before_arrow?(line) do
    case Regex.run(~r/(\S)\s*->/, line, capture: :all_but_first) do
      [<<c>>] when c >= ?a and c <= ?z -> false
      [<<c>>] when c >= ?A and c <= ?Z -> false
      [<<c, _::binary>>] when c == ?_ -> false
      [_] -> true
      _ -> false
    end
  end

  defp fix_line(line) do
    # Find the lambda pattern and wrap with fn ... end
    case Regex.run(@lambda_params_pattern, line, return: :index) do
      [{match_start, match_length}, {param_start, param_length}] ->
        params = binary_part(line, param_start, param_length)
        before = binary_part(line, 0, match_start)

        after_match =
          binary_part(
            line,
            match_start + match_length,
            byte_size(line) - match_start - match_length
          )

        # Find the body and any trailing content (like closing paren)
        {body, suffix} = split_body_and_suffix(after_match)

        before <> "fn " <> String.trim(params) <> " -> " <> String.trim(body) <> " end" <> suffix

      _ ->
        line
    end
  end

  defp split_body_and_suffix(after_match) do
    trimmed = String.trim(after_match)

    # If it ends with ), we want to put end before the )
    if String.ends_with?(trimmed, ")") do
      # Find the position of the last )
      last_paren_idx = find_last_paren(trimmed)

      if last_paren_idx >= 0 do
        {body, suffix} = String.split_at(trimmed, last_paren_idx)
        {body, suffix}
      else
        {trimmed, ""}
      end
    else
      {trimmed, ""}
    end
  end

  defp find_last_paren(str) do
    # Find the index of the last ) in the string
    str
    |> String.to_charlist()
    |> Enum.with_index()
    |> Enum.filter(fn {c, _} -> c == ?) end)
    |> Enum.map(fn {_, idx} -> idx end)
    |> List.last(-1)
  end

  defp build_issue(line_no) do
    %Issue{
      rule: :prefer_fn_end_syntax,
      message:
        "Python-style lambda syntax detected. " <>
          "Wrap with `fn ... end` for valid Elixir.",
      meta: %{line: line_no}
    }
  end
end
