defmodule Credence.Pattern.NoCaseDigitToInteger do
  @moduledoc """
  Detects `case` expressions that map single-digit string characters ("0"–"9")
  to their integer equivalents (0–9) and rewrites them to `String.to_integer/1`.

  LLMs frequently generate this pattern when translating digit-conversion code
  from other languages (e.g. Python's `int(char)`). In Elixir the idiomatic
  replacement is `String.to_integer/1`, which works on single-character strings.

  ## Flagged patterns

      case digit do
        "0" -> 0
        "1" -> 1
        "2" -> 2
        "3" -> 3
        "4" -> 4
        "5" -> 5
        "6" -> 6
        "7" -> 7
        "8" -> 8
        "9" -> 9
      end

  ## Good

      String.to_integer(digit)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  # Pre-sorted list of {string, integer} pairs for "0"–"9".
  @digit_pairs Enum.map(0..9, fn n -> {Integer.to_string(n), n} end)

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case extract_digit_case(node) do
          {:ok, meta} ->
            issue = %Issue{
              rule: :no_case_digit_to_integer,
              message:
                "`case` mapping digit strings to integers — " <>
                  "use `String.to_integer/1` instead.",
              meta: %{line: Keyword.get(meta, :line)}
            }

            {node, [issue | issues]}

          :error ->
            {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, fn
      # case subject do ... end
      {:case, _meta, [subject, kw]} = node when is_list(kw) ->
        maybe_replace(node, subject, kw)

      # subject |> case do ... end
      {:|>, _pipe_meta, [subject, {:case, _case_meta, kw}]} = node when is_list(kw) ->
        maybe_replace(node, subject, kw)

      node ->
        node
    end)
  end

  defp maybe_replace(node, subject, kw) do
    case extract_do_clauses(kw) do
      nil -> node
      clauses -> if digit_mapping_clauses?(clauses), do: string_to_integer_call(subject), else: node
    end
  end

  defp extract_digit_case({:case, meta, [_subject, kw]}) when is_list(kw) do
    case extract_do_clauses(kw) do
      nil -> :error
      clauses -> if digit_mapping_clauses?(clauses), do: {:ok, meta}, else: :error
    end
  end

  defp extract_digit_case({:case, meta, [kw]}) when is_list(kw) do
    case extract_do_clauses(kw) do
      nil -> :error
      clauses -> if digit_mapping_clauses?(clauses), do: {:ok, meta}, else: :error
    end
  end

  defp extract_digit_case(_), do: :error

  defp extract_do_clauses([do: clauses]) when is_list(clauses), do: clauses

  defp extract_do_clauses([{{:__block__, _, [:do]}, clauses}]) when is_list(clauses),
    do: clauses

  defp extract_do_clauses(_), do: nil

  defp digit_mapping_clauses?(clauses) when length(clauses) == 10 do
    pairs =
      Enum.map(clauses, fn
        {:->, _, [[pattern], result]} ->
          {unwrap_literal(pattern), unwrap_literal(result)}

        _ ->
          :invalid
      end)

    not Enum.any?(pairs, &(&1 == :invalid)) and Enum.sort(pairs) == @digit_pairs
  end

  defp digit_mapping_clauses?(_), do: false

  defp unwrap_literal({:__block__, _, [val]}), do: val
  defp unwrap_literal(val), do: val

  defp string_to_integer_call(subject) do
    {{:., [], [{:__aliases__, [], [:String]}, :to_integer]}, [], [subject]}
  end
end
