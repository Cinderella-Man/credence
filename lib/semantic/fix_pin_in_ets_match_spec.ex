defmodule Credence.Semantic.FixPinInEtsMatchSpec do
  @moduledoc """
  Fixes the common LLM mistake of using the pin operator `^` outside a match
  context — most often inside ETS match specs passed to `:ets.match_delete/2`,
  `:ets.match_object/2`, and similar.

  The pin operator `^` is only valid inside match contexts (function heads,
  `case` clauses, `=` left-hand sides). In an ETS match spec a bound variable
  already acts as a pin — `^name` is invalid there. The compiler rejects it
  with:

      misplaced operator ^name

      The pin operator ^ is supported only inside matches or inside custom macros.

  In any non-match context a bare variable already denotes its bound value,
  which is exactly what the author meant the pin to express, so the fix strips
  the `^` prefix from the flagged pin.

  ## Matching vs fixing

  `match?/1` sees only the diagnostic, so it claims every `misplaced operator
  ^…` error. The diagnostic carries the exact `{line, column}` of the offending
  `^` plus the variable name, and `fix/2` strips only the pin node at that
  position with that name — never another pin sharing the line (a valid pin
  inside e.g. `match?/2` on the same line is left alone). The
  `should_report?/2` phase hook reports an issue only when the fix would
  actually rewrite the source.

  ## Bad

      defmodule FixPinInEtsMatchSpecFPIEMS do
        def reset(table, name) do
          :ets.match_delete(table, {{^name, :_}, :_})
        end
      end

  ## Good

      defmodule FixPinInEtsMatchSpecFPIEMS do
        def reset(table, name) do
          :ets.match_delete(table, {{name, :_}, :_})
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_prefix "misplaced operator ^"
  @pinned_var ~r/\Amisplaced operator \^(\S+)/

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.starts_with?(msg, @match_prefix)
  end

  def match?(_), do: false

  @doc """
  Phase hook (`Credence.Semantic.match_rules/2`): report an issue only when
  `fix/2` would actually rewrite the source, so misplaced-pin diagnostics
  whose exact pin cannot be located are not attributed to this rule.
  """
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_pin_in_ets_match_spec,
      message: "pin operator ^ is only valid inside a match; stripping ^",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg, position: {target_line, target_col}}) do
    with [_, var] <- Regex.run(@pinned_var, msg),
         {:ok, ast} <- Sourceror.parse_string(source) do
      pinned = String.to_atom(var)

      result =
        Macro.prewalk(ast, fn
          {:^, meta, [{^pinned, _, ctx} = inner]} = node when is_atom(ctx) ->
            if Keyword.get(meta, :line) == target_line and
                 Keyword.get(meta, :column) == target_col do
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

  # Without an exact column there is no way to tell the flagged pin apart from
  # a valid pin of the same variable on the same line, so leave the source
  # untouched (`should_report?/2` then keeps the diagnostic unclaimed).
  def fix(source, _diagnostic), do: source

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
