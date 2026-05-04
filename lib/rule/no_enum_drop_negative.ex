defmodule Credence.Rule.NoEnumDropNegative do
  @moduledoc """
  Performance rule: Detects `Enum.drop(list, -n)` where `n` is a positive
  integer literal.

  For linked lists, `Enum.drop(list, -n)` must traverse to the end of the
  list to figure out where to cut, making it O(n). This often indicates
  the algorithm should be restructured to avoid needing to trim from the
  tail of a linked list.

  The auto-fix replaces `Enum.drop(list, -n)` with `Enum.slice(list, 0..-(n+1)//1)`,
  which has equivalent semantics. If performance is critical, consider
  restructuring to avoid tail-trimming entirely.

  ## Bad

      list |> Enum.drop(-1)

      Enum.drop(list, -3)

  ## Good

      # If building the list yourself, drop the head before reversing:
      [_ | rest] = reversed_list
      Enum.reverse(rest)

      # Or use Enum.slice/2 if you know the desired length:
      Enum.slice(list, 0..-2//1)
  """
  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Direct: Enum.drop(list, -1)
        {{:., _, [{:__aliases__, _, [:Enum]}, :drop]}, meta, [_, {:-, _, [n]}]} = node, issues
        when is_integer(n) and n > 0 ->
          {node, [build_issue(n, meta) | issues]}

        # Piped: list |> Enum.drop(-1)
        {{:., _, [{:__aliases__, _, [:Enum]}, :drop]}, meta, [{:-, _, [n]}]} = node, issues
        when is_integer(n) and n > 0 ->
          {node, [build_issue(n, meta) | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    source
    # First pass: piped Enum.drop(-N) has exactly one arg (no commas at top level)
    |> fix_piped_drops()
    # Second pass: direct Enum.drop(expr, -N) with paren matching
    |> fix_direct_drops()
  end

  # Piped: Enum.drop(-N) → Enum.slice(0..-(N+1)//1)
  # Safe regex — only one arg between the parens, always a negative literal.
  defp fix_piped_drops(source) do
    Regex.replace(~r/Enum\.drop\(\s*-(\d+)\s*\)/, source, fn _, n_str ->
      n = String.to_integer(n_str)
      "Enum.slice(0..#{-(n + 1)}//1)"
    end)
  end

  # Direct: Enum.drop(expr, -N) → Enum.slice(expr, 0..-(N+1)//1)
  # Uses paren-matching to correctly find the closing ) even when expr
  # contains nested parentheses (e.g. Map.values(map)).
  defp fix_direct_drops(source) do
    case :binary.match(source, "Enum.drop(") do
      :nomatch ->
        source

      {pos, len} ->
        before = binary_part(source, 0, pos)
        from_call = binary_part(source, pos, byte_size(source) - pos)
        open_idx = len

        case find_closing_paren(from_call, open_idx, 1) do
          nil ->
            source

          close_idx ->
            args_str = binary_part(from_call, open_idx, close_idx - open_idx)

            after_call =
              binary_part(from_call, close_idx + 1, byte_size(from_call) - close_idx - 1)

            # Greedy (.+) matches everything up to the LAST `, -N` — handles
            # commas inside nested calls like func(a, b) correctly.
            case Regex.run(~r/^(.+),\s*-(\d+)\s*$/s, args_str) do
              [_, expr, n_str] ->
                n = String.to_integer(n_str)
                replacement = "Enum.slice(#{expr}, 0..#{-(n + 1)}//1)"
                fix_direct_drops(before <> replacement <> after_call)

              _ ->
                # Not a negative-literal last arg; skip past this Enum.drop call
                skipped = binary_part(from_call, 0, close_idx + 1)
                before <> skipped <> fix_direct_drops(after_call)
            end
        end
    end
  end

  # Scan forward through `str` starting at byte `pos`, tracking paren depth.
  # Returns the index of the matching `)` or nil if not found.
  defp find_closing_paren(str, pos, depth) do
    if pos >= byte_size(str) do
      nil
    else
      char = binary_part(str, pos, 1)

      cond do
        char == "(" -> find_closing_paren(str, pos + 1, depth + 1)
        char == ")" and depth == 1 -> pos
        char == ")" -> find_closing_paren(str, pos + 1, depth - 1)
        true -> find_closing_paren(str, pos + 1, depth)
      end
    end
  end

  defp build_issue(n, meta) do
    %Issue{
      rule: :no_enum_drop_negative,
      message:
        "`Enum.drop(list, -#{n})` traverses the entire list to drop from the end. " <>
          "Restructure the algorithm to avoid tail-trimming on linked lists, " <>
          "or drop from the head of a reversed list instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
