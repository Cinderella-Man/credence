defmodule Credence.Semantic.FixEtsNewStringName do
  @moduledoc """
  Fixes string interpolation used as the table name argument to `:ets.new/2`.

  LLM-generated ETS code frequently passes a string interpolation
  (`"\#{name}_suffix"`) as the first argument to `:ets.new/2`, which requires
  an atom.  At runtime this raises `ArgumentError`.

  The fix converts `"\#{name}_data"` to `:"\#{name}_data"` (atom interpolation)
  on the line the diagnostic flags.  Both forms produce the same atom value,
  so the rewrite is semantically identical.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "table name to :ets.new/2 — use atom interpolation"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_ets_new_string_name,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    case line(diagnostic) do
      line_no when is_integer(line_no) ->
        source
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.map_join("\n", fn
          {text, ^line_no} ->
            # Replace string interpolation `"#...` with atom interpolation
            # `:"#...` on the flagged line only.  The negative lookbehind
            # avoids double-prefixing `:"#` that is already correct.
            Regex.replace(~r/(?<!:)"#/, text, ":\"#")

          {text, _} ->
            text
        end)

      _ ->
        source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
  defp line(_), do: nil
end
