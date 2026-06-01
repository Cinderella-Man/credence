defmodule Credence.Pattern.AvoidGraphemesForByteIteration do
  @moduledoc """
  Check-only rule: Detects `String.graphemes/1` piped into an `Enum` function
  where the callback/predicate operates on integer codepoints.

  `String.graphemes/1` splits into grapheme strings — each a single-char
  binary. When the callback uses integer/byte-value comparisons (e.g.
  char literals like `?A`, range guards) or binary pattern matching
  (`<<char>>`) to extract byte values, `String.to_charlist/1` is more
  direct: it yields integers without the intermediate binary wrapping.

  Covered Enum functions: `all?/2`, `any?/2`, `each/2`, `map/2`,
  `filter/2`, `flat_map/2`, `reduce/3`.

  This rule fires when:
  - The predicate contains **visible integer comparisons** (char literals,
    integer ranges), OR
  - The callback uses `<<char>>` binary pattern matching in its arguments
    to extract byte values from graphemes.

  It does NOT fire for:
  - Opaque function captures (`&func/1`) — cannot verify the callback
    expects integers vs strings.
  - String/regex operations — the callback needs grapheme strings.
  - Callbacks that treat graphemes as strings (concatenation, etc.).

  This avoids contradictions with `avoid_charlist_for_iteration`, which
  recommends graphemes for general iteration.

  ## Bad

      string |> String.graphemes() |> Enum.all?(fn c -> c >= ?0 and c <= ?9 end)
      string |> String.graphemes() |> Enum.any?(fn c -> c in ?A..?Z end)
      string |> String.graphemes() |> Enum.reduce(0, fn <<char>>, acc -> acc * 26 + char end)
      string |> String.graphemes() |> Enum.map(fn <<char>> -> char - ?A + 1 end)

  ## Good (not flagged — opaque capture, can't verify)

      string |> String.graphemes() |> Enum.all?(&hex_digit?/1)

  ## Good (use Regex.match? directly — no iteration needed)

      Regex.match?(~r/[^a-zA-Z0-9]/, string)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipe: ... |> String.graphemes() |> Enum.all?(pred)
        {:|>, meta, [lhs, rhs]} = node, issues ->
          if iteration_call?(rhs) and immediate_graphemes?(lhs) and
               (predicate_expects_integers?(rhs) or
                  callback_uses_binary_extraction?(rhs)) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # Single-arg Enum functions: all?, any?, each, map, filter, flat_map
  defp iteration_call?({{:., _, [{:__aliases__, _, [:Enum]}, func]}, _, [pred]})
       when func in [:all?, :any?, :each, :map, :filter, :flat_map] and is_tuple(pred),
       do: true

  # Two-arg Enum function: reduce (init + callback)
  defp iteration_call?({{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [_, pred]})
       when is_tuple(pred),
       do: true

  defp iteration_call?(_), do: false

  defp immediate_graphemes?({:|>, _, [_, rhs]}), do: graphemes_call?(rhs)
  defp immediate_graphemes?(other), do: graphemes_call?(other)

  defp graphemes_call?({{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, args})
       when is_list(args),
       do: true

  defp graphemes_call?(_), do: false

  # Check if the predicate in Enum.all?/any?/each expects integer codepoints.
  # Only returns true when we can VERIFY integer comparisons in the predicate.
  # Opaque captures (&func/1) return false — we can't tell what they expect.
  defp predicate_expects_integers?(
         {{:., _, [{:__aliases__, _, [:Enum]}, _]}, _, [pred]}
       ) do
    case pred do
      # Opaque capture: &func/1 or &Mod.func/1 — can't verify
      {:&, _, [{:/, _, _}]} ->
        false

      # Inline body (anonymous fn or capture with body) — check for integer comparisons
      _ ->
        predicate_body_has_integer_comparison?(pred) and
          not predicate_uses_binary_matching?(pred)
    end
  end

  defp predicate_expects_integers?(_), do: false

  # Check if the callback uses <<...>> binary pattern matching in its arguments.
  # After String.graphemes(), this means the code extracts byte values from
  # graphemes — to_charlist/1 would be more direct.
  defp callback_uses_binary_extraction?(
         {{:., _, [{:__aliases__, _, [:Enum]}, _]}, _, args}
       ) do
    callback = List.last(args)

    case callback do
      {:fn, _, clauses} ->
        Enum.any?(clauses, fn {:->, _, [patterns, _body]} ->
          Enum.any?(patterns, &binary_pattern?/1)
        end)

      _ ->
        false
    end
  end

  defp callback_uses_binary_extraction?(_), do: false

  defp binary_pattern?({:<<>>, _, _}), do: true
  defp binary_pattern?({:when, _, [inner | _]}), do: binary_pattern?(inner)
  defp binary_pattern?(_), do: false

  # Walk predicate AST looking for comparisons with integer literals (char values).
  # Handles both bare integers and Sourceror-wrapped {:__block__, _, [int]}.
  defp predicate_body_has_integer_comparison?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        _node, true = acc ->
          {nil, acc}

        # Comparison operators with at least one integer operand
        {op, _, [left, right]} = node, acc when op in [:>=, :<=, :>, :<, :==, :!=] ->
          {node, acc or integer_literal?(left) or integer_literal?(right)}

        # Range with integer endpoints (e.g. ?0..?9)
        {:"..", _, [left, right]} = node, acc ->
          {node, acc or (integer_literal?(left) and integer_literal?(right))}

        # in/2 with range (e.g. c in ?A..?Z)
        {:in, _, [_, {:"..", _, [left, right]}]} = node, acc ->
          {node, acc or (integer_literal?(left) and integer_literal?(right))}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp integer_literal?(n) when is_integer(n), do: true
  defp integer_literal?({:__block__, _, [n]}) when is_integer(n), do: true
  defp integer_literal?(_), do: false

  # Detect binary pattern matching (<<...>>) in the predicate — this means
  # the predicate expects binary/grapheme inputs, not integers.
  defp predicate_uses_binary_matching?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        _node, true = acc ->
          {nil, acc}

        {:<<>>, _, _} = node, _ ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp build_issue(meta) do
    %Issue{
      rule: :avoid_graphemes_for_byte_iteration,
      message: """
      `String.graphemes/1` produces single-char binaries, but the callback \
      treats them as byte values (via integer comparisons or `<<char>>` \
      binary pattern matching). `String.to_charlist/1` yields integers \
      directly and avoids the intermediate binary wrapping.

      Replace `String.graphemes/1` with `String.to_charlist/1`:

          # Before (creates binary graphemes, extracts bytes manually):
          string |> String.graphemes() |> Enum.reduce(0, fn <<char>>, acc -> acc + char end)

          # After (yields integers directly):
          string |> String.to_charlist() |> Enum.reduce(0, fn char, acc -> acc + char end)
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
