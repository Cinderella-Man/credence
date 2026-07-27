defmodule Credence.Semantic.FixPinInEtsMatchSpec do
  @moduledoc """
  Fixes the common LLM mistake of using the pin operator `^` inside ETS match
  specs passed to `:ets.match_delete/2`, `:ets.match_object/2`, and similar.

  The pin operator `^` is only valid inside match contexts (function heads,
  `case` clauses, `=` left-hand sides). In an ETS match spec a bound variable
  already acts as a pin — `^name` is syntactically invalid there. The compiler
  rejects it with:

      misplaced operator ^name
      The pin operator ^ is supported only inside matches or inside custom macros.

  The fix deterministically strips the `^` prefix, leaving the bare variable
  name. This is correct because the match spec already references the bound
  variable.
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
      rule: :fix_pin_in_ets_match_spec,
      message: "pin operator ^ in ETS match spec is invalid; stripping ^",
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
