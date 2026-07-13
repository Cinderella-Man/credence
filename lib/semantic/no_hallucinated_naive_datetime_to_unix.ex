defmodule Credence.Semantic.NoHallucinatedNaiveDatetimeToUnix do
  @moduledoc """
  Fixes the compiler error caused by `NaiveDateTime.to_unix/2`.

  LLMs frequently hallucinate a two-argument form `NaiveDateTime.to_unix(dt, :second)`,
  but `NaiveDateTime.to_unix/2` does not exist — only `to_unix/1` is defined, and it
  always returns seconds. The second argument is meaningless.

  The compiler emits:

      "NaiveDateTime.to_unix/2 is undefined or private. Did you mean one of:

            * to_unix/1"

  The existing `UndefinedFunction` rule matches the diagnostic but cannot repair it.
  This rule strips the second argument, yielding the idiomatic `NaiveDateTime.to_unix(dt)`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "NaiveDateTime.to_unix/2"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg) and String.contains?(msg, "is undefined or private")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_hallucinated_naive_datetime_to_unix,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {{:., dot_meta,
            [
              {:__aliases__, alias_meta, [:NaiveDateTime]},
              :to_unix
            ]}, call_meta, [_first_arg | _rest] = args},
          _acc
          when length(args) == 2 ->
            # Strip the hallucinated second argument
            new_node =
              {{:., dot_meta,
                [
                  {:__aliases__, alias_meta, [:NaiveDateTime]},
                  :to_unix
                ]}, call_meta, [hd(args)]}

            {new_node, true}

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
