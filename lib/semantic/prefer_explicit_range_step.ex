defmodule Credence.Semantic.PreferExplicitRangeStep do
  @moduledoc """
  Makes the implicit step of a descending literal range explicit.

  Since Elixir 1.19 a fully-literal range whose default step is `-1`
  (`first > last`, e.g. `1..-2`, `10..-5`, `5..1`) emits a deprecation warning:

      1..-2 has a default step of -1, please write 1..-2//-1 instead

  Under `--warnings-as-errors` this blocks compilation. The fix appends the
  step the compiler itself reports (`//-1`), which is a **no-op on behaviour**:
  the warning states that `-1` is already the current default step, so
  `1..-2` and `1..-2//-1` are the identical `Range` value. We apply the
  compiler's own stated equivalence — the message carries both the original
  range text and its explicit form verbatim.

  The warning fires only when both endpoints are literals (the compiler must be
  able to compute the default step); a range with a variable endpoint
  (`a..-1`) produces no diagnostic and is left alone.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  # "<range> has a default step of <n>, please write <range>//<n> instead"
  @message_re ~r/\A(.+?) has a default step of -?\d+, please write (.+?) instead/

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, "has a default step of") and
      String.contains?(msg, "please write")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :prefer_explicit_range_step,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) when is_binary(msg) do
    case Regex.run(@message_re, msg) do
      [_, original, explicit] ->
        # Replace only the exact range token: not preceded by a digit/dot and
        # not followed by a digit or `/` (so `1..-20`, `11..-2`, and an
        # already-stepped `1..-2//-1` are never partially matched).
        re = ~r/(?<![\d.])#{Regex.escape(original)}(?![\d\/])/
        Regex.replace(re, source, fn _ -> explicit end)

      _ ->
        source
    end
  end

  def fix(source, _diagnostic), do: source

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
