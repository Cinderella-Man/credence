defmodule Credence.Pattern.NoRedundantLengthWithRegex do
  @moduledoc """
  Flags redundant `String.length(x) == N` checks that are combined via
  `and` with a `Regex.match?/2` or `String.match?/2` call using an
  anchored regex whose fixed quantifier already ensures exactly N
  characters.

  The regex check alone is sufficient — the length check adds no value.

  ## Bad

      if String.length(code) == 6 and Regex.match?(~r/^[A-Z]{6}$/, code) do
        "valid"
      end

      String.length(digits) == 10 and String.match?(digits, ~r/^\d{10}$/)

  ## Good

      if Regex.match?(~r/^[A-Z]{6}$/, code) do
        "valid"
      end

      String.match?(digits, ~r/^\d{10}$/)
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:and, meta, [lhs, rhs]} = node, issues ->
          case find_redundant_length_match(lhs, rhs) do
            nil -> {node, issues}
            :lhs -> {node, [build_issue(meta, :lhs) | issues]}
            :rhs -> {node, [build_issue(meta, :rhs) | issues]}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {:and, _meta, [lhs, rhs]} = node ->
        case find_redundant_length_match(lhs, rhs) do
          :lhs -> rhs
          :rhs -> lhs
          nil -> node
        end

      node ->
        node
    end)
  end

  # Returns :lhs if lhs is the redundant length check, :rhs if rhs is,
  # nil if neither side matches the pattern.
  defp find_redundant_length_match(lhs, rhs) do
    cond do
      redundant_length_check?(lhs) and regex_match_call?(rhs) and
          length_matches_regex_quantifier?(lhs, rhs) ->
        :lhs

      redundant_length_check?(rhs) and regex_match_call?(lhs) and
          length_matches_regex_quantifier?(rhs, lhs) ->
        :rhs

      true ->
        nil
    end
  end

  # Matches `String.length(x) == N` (and reversed, === variants).
  # Sourceror wraps integer literals as {:__block__, meta, [N]}.
  # Single clause with both orderings to avoid overlapping patterns.
  defp redundant_length_check?({op, _, [a, b]}) when op in [:==, :===] do
    (string_length_call?(a) and literal_integer?(b)) or
      (string_length_call?(b) and literal_integer?(a))
  end

  defp redundant_length_check?(_), do: false

  defp string_length_call?({{:., _, [{:__aliases__, _, [:String]}, :length]}, _, [_]}), do: true
  defp string_length_call?(_), do: false

  # Sourceror wraps integer literals as {:__block__, meta, [N]} where N
  # may appear as a charlist in inspection but is still an integer element.
  defp literal_integer?(n) when is_integer(n), do: true
  defp literal_integer?({:__block__, _, [n]}) when is_integer(n), do: true
  defp literal_integer?(_), do: false

  # Matches `Regex.match?(~r/.../, x)` or `String.match?(x, ~r/.../)`
  defp regex_match_call?(
         {{:., _, [{:__aliases__, _, [:Regex]}, :match?]}, _, [_regex, _subject]}
       ),
       do: true

  defp regex_match_call?(
         {{:., _, [{:__aliases__, _, [:String]}, :match?]}, _, [_subject, _regex]}
       ),
       do: true

  defp regex_match_call?(_), do: false

  # Extracts the integer from the length check and the regex, then
  # verifies the regex has ^...$ anchors with a {N} quantifier where N
  # matches the length integer.
  defp length_matches_regex_quantifier?(length_side, regex_side) do
    with n when is_integer(n) <- extract_length_int(length_side),
         regex when not is_nil(regex) <- extract_regex(regex_side) do
      anchored_fixed_quantifier?(regex, n)
    else
      _ -> false
    end
  end

  defp extract_length_int({op, _, [a, b]}) when op in [:==, :===] do
    cond do
      string_length_call?(a) -> unwrap_int(b)
      string_length_call?(b) -> unwrap_int(a)
      true -> nil
    end
  end

  defp extract_length_int(_), do: nil

  defp unwrap_int(n) when is_integer(n), do: n
  defp unwrap_int({:__block__, _, [n]}) when is_integer(n), do: n
  defp unwrap_int(_), do: nil

  defp extract_regex(
         {{:., _, [{:__aliases__, _, [:Regex]}, :match?]}, _, [regex, _subject]}
       ) do
    extract_regex_literal(regex)
  end

  defp extract_regex(
         {{:., _, [{:__aliases__, _, [:String]}, :match?]}, _, [_subject, regex]}
       ) do
    extract_regex_literal(regex)
  end

  # ~r/.../ is parsed as a sigil call: {:sigil_r, _, [regex_string, modifiers]}
  defp extract_regex_literal({:sigil_r, _, [{:<<>>, _, [pattern]}, _modifiers]}), do: pattern
  defp extract_regex_literal(_), do: nil

  # Checks if the regex pattern is anchored at both ends with a fixed
  # quantifier {N} where N matches the expected count.
  defp anchored_fixed_quantifier?(pattern, expected_n) when is_binary(pattern) do
    pattern
    |> String.trim()
    |> case do
      "^" <> rest ->
        case String.split(rest, "$", parts: 2) do
          [inner, ""] -> inner_anchors_fixed?(inner, expected_n)
          _ -> false
        end

      _ ->
        false
    end
  end

  defp anchored_fixed_quantifier?(_, _), do: false

  defp inner_anchors_fixed?(inner, expected_n) do
    # Match raw regex patterns like \d{10}, \w{5}, \s{3}, [0-9]{6}, .{4}, a{5}
    # The inner part between ^ and $ must be a single character class with {N}.
    # Note: the inner string contains literal backslashes for \d, \w, etc.
    case Regex.run(~r/^\\[dwsbB]\{(\d+)\}$/, inner) do
      [_, n_str] ->
        String.to_integer(n_str) == expected_n

      _ ->
        # Character class like [0-9]{6} or single char like a{5}
        case Regex.run(~r/^(\[.*?\]|.)\{(\d+)\}$/, inner) do
          [_, _class, n_str] -> String.to_integer(n_str) == expected_n
          _ -> false
        end
    end
  end

  defp build_issue(meta, redundant_side) do
    side_desc =
      case redundant_side do
        :lhs -> "left"
        :rhs -> "right"
      end

    %Issue{
      rule: :no_redundant_length_with_regex,
      message:
        "The #{side_desc}-hand `String.length/1` check is redundant — the anchored regex " <>
          "with a fixed quantifier already ensures the exact length. Remove the length check.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
