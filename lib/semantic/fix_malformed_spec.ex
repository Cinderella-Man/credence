defmodule Credence.Semantic.FixMalformedSpec do
  @moduledoc """
  Fixes `@spec` declarations where the `::` return-type separator is misplaced
  inside the argument parentheses.

  LLMs translating from Python sometimes put the whole spec — parameter types
  *and* return type — inside one pair of parentheses:

      # Before (does not compile):
      @spec max_product(list(integer()) :: integer())

      # After:
      @spec max_product(list(integer())) :: integer()

  ## Why this is a Semantic rule and not a Syntax one

  It was a Syntax rule, and it could never fire. `::` is an ordinary
  right-associative binary operator (`elixir_parser.yrl`, `Right 60
  type_op_eol`), so `f(a :: b)` is a **well-formed call argument** and
  `@spec max_product(list(integer()) :: integer())` *parses*. The Syntax phase
  only runs on source that fails to parse, so the rule sat in the wrong phase
  from the day it landed — its own moduledoc said "## Bad (won't parse)", which
  one `Code.string_to_quoted/1` call at authoring time would have refuted. The
  T1 pipeline-witness gate caught it (docs/22 T3.8).

  The failure mode is real, though: the line parses and then fails to *compile*,
  because a spec has to declare a return type. The compiler says so precisely,
  at `severity: :error`, naming the offending spec:

      type specification missing return type: max_product(list(integer()) :: integer())

  Nothing claimed that diagnostic. So the rule is re-homed rather than retired,
  keyed on what the compiler actually emits instead of on a parse failure that
  never happens. The rewrite itself is unchanged.

  ## What is not flagged

  A valid spec with **named** arguments (`@spec f(count :: integer()) ::
  atom()`) declares its return type outside the parens and therefore compiles,
  so it never produces this diagnostic and is never seen here. The line rewrite
  additionally declines any line that already has a `::` after the closing
  paren, so even a hand-fed one is left alone.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "type specification missing return type:"

  @impl true
  def match?(%{message: msg}) when is_binary(msg), do: String.contains?(msg, @match_msg)
  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      # Semantic and Pattern issue atoms are derived from the module name
      # (`Credence.RuleName.from_module/1`), which is how the T1 witness gate
      # attributes an issue back to its rule. Only Syntax atoms are
      # author-chosen — carrying this rule's old Syntax atom `:malformed_spec`
      # across the phase boundary made it unattributable, and T1 caught that.
      rule: :fix_malformed_spec,
      message:
        "The `::` return type separator is inside the argument parens. " <>
          "Move `)` before `::` — e.g. `@spec func(type) :: return`.",
      meta: %{line: line_of(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    lines = String.split(source, "\n")
    idx = line_of(diagnostic) - 1

    case Enum.at(lines, idx) do
      nil ->
        source

      line ->
        case fix_line(line) do
          ^line -> source
          fixed -> lines |> List.replace_at(idx, fixed) |> Enum.join("\n")
        end
    end
  end

  # The diagnostic carries the `@spec` line directly, so the rewrite is scoped
  # to it. `position` is a bare line here, but the behaviour admits `{line, col}`
  # too and a rule that assumed one shape would crash on the other.
  defp line_of(%{position: {line, _col}}), do: line
  defp line_of(%{position: line}) when is_integer(line), do: line
  defp line_of(_), do: 0

  defp fix_line(line) do
    with {:ok, prefix, inner, after_close} <- extract_spec_parts(line),
         false <- String.contains?(after_close, "::"),
         pos when is_integer(pos) <- find_last_separator(inner),
         {params_part, "::" <> return_part} = String.split_at(inner, pos),
         false <- named_argument?(params_part) do
      "#{prefix}(#{String.trim_trailing(params_part)}) :: #{String.trim_leading(return_part)}#{after_close}"
    else
      _ -> line
    end
  end

  defp named_argument?(params_part) do
    Regex.match?(~r/(?:^|,)\s*[a-z_][a-zA-Z0-9_]*\s*$/, params_part)
  end

  # Extracts the prefix (`@spec func_name`), the content between the outermost
  # parens, and whatever follows the matching close paren.
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

  # Finds the matching `)` for an already-opened `(` (depth starts at 1).
  defp find_matching_close(chars), do: do_close(chars, 1, [])

  defp do_close([], _depth, _acc), do: :unbalanced

  defp do_close([?) | rest], 1, acc) do
    {:ok, acc |> Enum.reverse() |> List.to_string(), List.to_string(rest)}
  end

  defp do_close([?) | rest], depth, acc), do: do_close(rest, depth - 1, [?) | acc])
  defp do_close([?( | rest], depth, acc), do: do_close(rest, depth + 1, [?( | acc])
  defp do_close([c | rest], depth, acc), do: do_close(rest, depth, [c | acc])

  # Character position of the LAST `::` at paren depth 0 within `content`.
  defp find_last_separator(content), do: content |> String.to_charlist() |> do_sep(0, 0, nil)

  defp do_sep([], _pos, _depth, last), do: last
  defp do_sep([?( | rest], pos, depth, last), do: do_sep(rest, pos + 1, depth + 1, last)
  defp do_sep([?) | rest], pos, depth, last), do: do_sep(rest, pos + 1, depth - 1, last)
  defp do_sep([?:, ?: | rest], pos, 0, _last), do: do_sep(rest, pos + 2, 0, pos)
  defp do_sep([_ | rest], pos, depth, last), do: do_sep(rest, pos + 1, depth, last)
end
