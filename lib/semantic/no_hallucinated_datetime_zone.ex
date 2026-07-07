defmodule Credence.Semantic.NoHallucinatedDatetimeZone do
  @moduledoc """
  Fixes compiler warnings about hallucinated `.zone` on DateTime structs.

  LLMs frequently hallucinate `dt.zone` instead of the correct `dt.time_zone`
  when accessing a DateTime's timezone. The compiler emits a warning:

      "unknown key .zone in expression: dt.zone"

  The fix replaces `.zone` with `.time_zone` on the flagged variable, leaving
  other struct fields (e.g. `.zone_abbr`) untouched.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "unknown key .zone in expression:"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_hallucinated_datetime_zone,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    with msg when is_binary(msg) <- Map.get(diagnostic, :message),
         {:ok, var} <- extract_var(msg) do
      # Replace `var.zone` with `var.time_zone`, word-boundary-anchored so
      # `.zone_abbr` is never touched.
      Regex.replace(~r/\b#{Regex.escape(var)}\.zone\b/, source, "#{var}.time_zone")
    else
      _ -> source
    end
  end

  # Extract the variable name from the diagnostic's indented expression line.
  # The message contains e.g. "    dt.zone" — grab the identifier before ".zone".
  defp extract_var(msg) do
    case Regex.run(~r/\b([a-z_][a-z0-9_]*)\.zone\b/, msg) do
      [_, var] -> {:ok, var}
      _ -> :error
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
