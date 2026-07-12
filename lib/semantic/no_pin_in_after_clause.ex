defmodule Credence.Semantic.NoPinInAfterClause do
  @moduledoc """
  Fixes the common LLM mistake of using the pin operator `^` in a `receive`
  `after` clause.

  LLMs write `^timeout_ms` in `after` clauses, but `after` evaluates an
  expression — it never matches a pattern. The compiler rejects this with:

      misplaced operator ^timeout_ms
      The pin operator ^ is supported only inside matches or inside custom macros.

  The fix strips the `^`, leaving the bare variable — deterministic, always
  correct, and safe because `after` is an expression context, not a pattern.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_prefix "misplaced operator ^"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.starts_with?(msg, @match_prefix)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_pin_in_after_clause,
      message: "pin operator ^ in after clause is invalid; stripping ^",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    target_line = line(diagnostic)

    with {:ok, ast} <- Sourceror.parse_string(source) do
      result =
        Macro.prewalk(ast, fn
          {:"^", meta, [inner]} = node ->
            if Keyword.get(meta, :line) == target_line do
              inner
            else
              node
            end

          other ->
            other
        end)

      if result == ast do
        source
      else
        Sourceror.to_string(result)
      end
    else
      _ -> source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
