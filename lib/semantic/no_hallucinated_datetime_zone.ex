defmodule Credence.Semantic.NoHallucinatedDatetimeZone do
  @moduledoc """
  Fixes compiler warnings about hallucinated `.zone` on DateTime structs.

  LLMs frequently hallucinate `dt.zone` instead of the correct `dt.time_zone`
  when accessing a DateTime's timezone. The compiler emits a warning:

      "unknown key .zone in expression: dt.zone"

  The fix replaces `.zone` with `.time_zone` on the flagged variable, anchored
  at the diagnostic's line so a legitimate `.zone` field on some *other* struct
  that happens to share the variable name (on a different line) is left alone,
  and leaving other struct fields (e.g. `.zone_abbr`) untouched. Each flagged
  occurrence carries its own diagnostic, so every real hallucination is still
  fixed within the pass.

  ## Bad

      defmodule DatetimeZoneWitnessNHDZ do
        def f(%DateTime{} = dt), do: dt.zone
      end

  ## Good

      defmodule DatetimeZoneWitnessNHDZ do
        def f(%DateTime{} = dt), do: dt.time_zone
      end
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
         line_no when is_integer(line_no) <- line(diagnostic),
         {:ok, var} <- extract_var(msg) do
      # Replace `var.zone` with `var.time_zone` on the flagged line only,
      # word-boundary-anchored so `.zone_abbr` is never touched. Restricting
      # to the flagged line keeps a valid `var.zone` (a real field on another
      # struct that reuses the name) on an unflagged line untouched.
      pattern = ~r/\b#{Regex.escape(var)}\.zone\b/
      replacement = "#{var}.time_zone"

      source
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn
        {text, ^line_no} -> Regex.replace(pattern, text, replacement)
        {text, _} -> text
      end)
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

  defp line(%{position: {line, _col}}) when is_integer(line), do: line
  defp line(%{position: line}) when is_integer(line), do: line
  defp line(_), do: nil
end
