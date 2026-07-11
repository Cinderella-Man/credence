defmodule Credence.Semantic.FixHallucinatedNaiveDatetimeAccessor do
  @moduledoc """
  Fixes compiler warnings about hallucinated NaiveDateTime accessor functions.

  LLMs frequently hallucinate `NaiveDateTime.minute/1`, `.hour/1`, `.day/1`,
  `.month/1`, and `.day_of_week/1` — accessor functions that do not exist in
  Elixir's `NaiveDateTime` module. These produce compiler warnings:

      "NaiveDateTime.minute/1 is undefined or private"

  The correct idiom is struct field access: `dt.minute`, `dt.hour`, `dt.day`,
  `dt.month`, `dt.day_of_week`. The fix rewrites the nonexistent remote call
  into the equivalent field-access expression.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @accessors ~w(minute hour day month day_of_week)a
  @match_pattern ~r/NaiveDateTime\.(#{Enum.join(@accessors, "|")})\/1 is undefined or private/

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    Regex.match?(@match_pattern, msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_hallucinated_naive_datetime_accessor,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {{:., _dot_meta,
            [
              {:__aliases__, _alias_meta, [:NaiveDateTime]},
              accessor
            ]}, _call_meta, [{var_name, _var_meta, nil} = var]},
          _acc
          when accessor in @accessors and is_atom(var_name) ->
            replacement = {{:., [], [var, accessor]}, [no_parens: true], []}
            {replacement, true}

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
