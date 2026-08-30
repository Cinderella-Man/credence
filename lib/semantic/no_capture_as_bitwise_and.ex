defmodule Credence.Semantic.NoCaptureAsBitwiseAnd do
  @moduledoc """
  Repairs the common Python→Elixir translation error where `&` is written as
  the bitwise-AND operator.

  In Python (and C) `x & 1` means bitwise AND. In Elixir `&` is the *capture*
  operator, so `x & 1` parses as `x(&1)` — a call passing capture argument
  `&1` outside any `&(...)`. The compiler rejects it with an `:error`-severity
  diagnostic:

      capture argument &1 must be used within the capture operator &

  whose `{line, column}` points straight at the `&`.

  The code never compiles for any input, so this is a REPAIR: the fix rewrites
  the offending `IDENT & <integer>` to the idiomatic, fully-qualified
  `Bitwise.band(IDENT, <integer>)` (no `import` needed). It is targeted by the
  diagnostic column, so only that one operator changes — never a legitimate
  capture elsewhere on the line (`&foo/1`, `&(&1 + 1)`).

  ## Integer literals

  Every Elixir integer literal form is accepted as the right operand: decimal
  (`255`), underscore-separated (`1_000`), hex (`0xFF`), binary (`0b1010`) and
  octal (`0o17`). For a long time only bare decimal digits were, so the very
  literals bitmask code is usually written with were cut in half:

      flags & 0xFF   ->  Bitwise.band(flags, 0)xFF   *** did not parse ***

  ## What is deliberately declined

  Python's `&` binds *looser* than every arithmetic and shift operator, so the
  operands of the source `&` are whole expressions, not single tokens. This
  rule only ever rewrites a bare identifier against a literal, and declines
  anything where that would change the grouping or splice into the middle of a
  larger term:

      h * 31 + c & 0xFFFFFFFF    left operand is `(h * 31 + c)`, not `c`
      m.flags & 0xFF             a chain — the `Bitwise.band` would land after `m.`
      @state.flags & 0xFF        likewise, and `@` would capture the call
      :erlang.system_time & 0xFF likewise, and the `:` would make an atom of it
      -m.flags & 0xFF            the unary minus belongs inside the mask
      flags & 0xFF + 1           right operand is `(0xFF + 1)`
      naïve & 0xFF               a non-ASCII identifier byte precedes the match

  A declined line keeps its compile error, which is loud. Rewriting it would
  produce code that compiles and returns a different number, which is not.

  Matching runs against a `Credence.SourceMask` shadow, so a `&` inside a
  string literal or comment is never mistaken for an operator.

  ## Bad

      defmodule CaptureAndCheckInteg1NCABA do
        def low_bit(n) do
          n & 1
        end
      end

  ## Good

      defmodule CaptureAndCheckInteg1NCABA do
        def low_bit(n) do
          Bitwise.band(n, 1)
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue
  alias Credence.SourceMask

  # `IDENT & <integer literal>` — the exact shape that yields the
  # "capture argument &N" diagnostic.
  #
  # Both operands are POSSESSIVE. A plain `\w+` hands characters back to
  # satisfy the trailing lookahead, which would let `0xFF` match as `0` with
  # `xFF` left over — the original defect, reintroduced by a lazy quantifier.
  @band_regex ~r/([A-Za-z_]\w*+)\s*&\s*(0[xXbBoO][0-9a-fA-F_]++|\d[\d_]*+)(?![\w.])/

  # Characters that may immediately precede the left operand. Anything else —
  # `.`, `@`, `:`, an operator, or a non-ASCII identifier byte — means the
  # match starts in the middle of a larger term.
  @safe_immediate_prefix [?\s, ?\t, ?(, ?,, ?[, ?{, ?=]

  # Operators that bind tighter than `&` in Python. One of these on either
  # side means the source's operand is a compound expression.
  @precedence_hazard [?+, ?-, ?*, ?/, ?%, ?^, ?&, ?|, ?~, ?<, ?>, ?., ?@]

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, "capture argument") and
      String.contains?(msg, "must be used within the capture operator")
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :no_capture_as_bitwise_and,
      message: msg,
      meta: %{line: extract_line(position)}
    }
  end

  @impl true
  def fix(source, %{position: {line, col}}) when is_integer(line) and is_integer(col) do
    rewrite(source, line, col)
  end

  def fix(source, %{position: line}) when is_integer(line) do
    rewrite(source, line, nil)
  end

  def fix(source, _diagnostic), do: source

  defp extract_line({line, _col}) when is_integer(line), do: line
  defp extract_line(line) when is_integer(line), do: line
  defp extract_line(_), do: nil

  # Matches are found in the masked shadow and spliced into the real line;
  # both are the same byte length and every code byte is identical, so the
  # match offsets are valid in either.
  defp rewrite(source, line_no, col) do
    source
    |> SourceMask.lines()
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn
      {{text, shadow}, ^line_no} -> rewrite_line(text, shadow, col)
      {{text, _shadow}, _} -> text
    end)
  end

  defp rewrite_line(text, shadow, col) do
    case pick_match(shadow, col) do
      nil ->
        text

      [{_ms, _ml}, {ls, ll}, {rs, rl}] ->
        lhs = binary_part(text, ls, ll)
        rhs = binary_part(text, rs, rl)
        before = binary_part(text, 0, ls)
        after_end = rs + rl
        rest = binary_part(text, after_end, byte_size(text) - after_end)

        before <> "Bitwise.band(" <> lhs <> ", " <> rhs <> ")" <> rest
    end
  end

  # The diagnostic column points at the `&`. When it is available, take the
  # match that owns that column so an unrelated `&` elsewhere on the line is
  # never touched; otherwise fall back to the first safe match.
  defp pick_match(shadow, col) do
    matches =
      @band_regex
      |> Regex.scan(shadow, return: :index)
      |> Enum.filter(&safe?(shadow, &1))

    case col do
      nil -> List.first(matches)
      _ -> Enum.find(matches, &owns_column?(shadow, &1, col))
    end
  end

  defp owns_column?(_shadow, [{ms, ml}, _lhs, _rhs], col),
    do: (col - 1) in ms..(ms + ml - 1)

  defp safe?(shadow, [{ms, ml}, {ls, _ll}, {rs, rl}]) do
    left_boundary_safe?(shadow, ls) and right_boundary_safe?(shadow, rs + rl) and
      ms + ml <= byte_size(shadow)
  end

  defp left_boundary_safe?(_shadow, 0), do: true

  defp left_boundary_safe?(shadow, start) do
    prev = :binary.at(shadow, start - 1)

    cond do
      prev not in @safe_immediate_prefix -> false
      prev in [?\s, ?\t] -> not hazard_before?(binary_part(shadow, 0, start - 1))
      true -> true
    end
  end

  defp hazard_before?(prefix) do
    case prefix |> String.trim_trailing() |> String.last() do
      nil -> false
      <<c>> -> c in @precedence_hazard
      _ -> true
    end
  end

  defp right_boundary_safe?(shadow, stop) when stop >= byte_size(shadow), do: true

  defp right_boundary_safe?(shadow, stop) do
    shadow
    |> binary_part(stop, byte_size(shadow) - stop)
    |> String.trim_leading()
    |> String.first()
    |> case do
      nil -> true
      <<c>> -> c not in @precedence_hazard
      _ -> false
    end
  end
end
