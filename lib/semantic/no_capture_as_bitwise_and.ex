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
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  # `IDENT & <integer literal>` — the exact shape that yields the
  # "capture argument &N" diagnostic. Used for the bare-line fallback when no
  # column is available.
  @band_regex ~r/([A-Za-z_]\w*)\s*&\s*(\d+)/

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
    fix_at_column(source, line, col)
  end

  def fix(source, %{position: line}) when is_integer(line) do
    update_line(source, line, fn text -> rewrite_first(text) || text end)
  end

  def fix(source, _diagnostic), do: source

  defp extract_line({line, _col}) when is_integer(line), do: line
  defp extract_line(line) when is_integer(line), do: line
  defp extract_line(_), do: nil

  defp fix_at_column(source, line_no, col) do
    update_line(source, line_no, fn text ->
      with true <- col >= 1 and col <= String.length(text),
           {before, "&" <> _ = at} <- String.split_at(text, col - 1),
           rewritten when is_binary(rewritten) <- rewrite_split(before, at) do
        rewritten
      else
        _ -> rewrite_first(text) || text
      end
    end)
  end

  # `before` ends with the left operand, `at` begins with `& <digits>`.
  # Rewrite just `LHS & DIGITS` → `Bitwise.band(LHS, DIGITS)`, keeping the
  # surrounding text on the line intact.
  defp rewrite_split(before, at) do
    with [lhs_with_ws] <- Regex.run(~r/[A-Za-z_]\w*\s*$/, before),
         [amp_with_digits] <- Regex.run(~r/^&\s*\d+/, at) do
      lhs = String.trim_trailing(lhs_with_ws)
      digits = amp_with_digits |> String.trim_leading("&") |> String.trim()
      prefix = binary_part(before, 0, byte_size(before) - byte_size(lhs_with_ws))

      rest =
        binary_part(at, byte_size(amp_with_digits), byte_size(at) - byte_size(amp_with_digits))

      prefix <> "Bitwise.band(" <> lhs <> ", " <> digits <> ")" <> rest
    else
      _ -> nil
    end
  end

  # Rewrite the first `IDENT & DIGITS` on a line; nil when the line has none.
  defp rewrite_first(text) do
    if Regex.match?(@band_regex, text) do
      Regex.replace(@band_regex, text, "Bitwise.band(\\1, \\2)", global: false)
    end
  end

  defp update_line(source, line_no, fun) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn
      {text, ^line_no} -> fun.(text)
      {text, _} -> text
    end)
  end
end
