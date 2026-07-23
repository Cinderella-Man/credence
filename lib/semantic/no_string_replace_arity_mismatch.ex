defmodule Credence.Semantic.NoStringReplaceArityMismatch do
  @moduledoc """
  Fixes `String.replace/3` calls where a multi-arity anonymous function is
  passed as the replacement for a regex literal.

  LLMs (familiar with Erlang's `re:replace/4`) write multi-arity callbacks:

      String.replace(str, ~r/(a)(b)/, fn full, cap1, cap2 -> ... end)

  `String.replace/3` requires `is_function(replacement, 1)` — only 1-arity
  functions — so the call raises `FunctionClauseError`. `Regex.replace/3`
  calls the function with the full match and each capture group as separate
  arguments, matching the multi-arity signature the LLM intended (it tolerates
  a callback arity that does not line up with the capture count: missing
  captures arrive as `""`, extra ones are dropped).

  The fix rewrites `String.replace(str, ~r/…/, fn ...)` to
  `Regex.replace(~r/…/, str, fn ...)`, preserving the callback verbatim.

  Only calls whose pattern is a `~r`/`~R` sigil are rewritten. `Regex.replace/3`
  requires a `%Regex{}` as its first argument, so rewriting a call with a binary
  pattern (`String.replace(str, "ab", fn a, b -> ... end)`) or an opaque one
  (a variable, `@attr`) would swap one `FunctionClauseError` for another instead
  of resolving the diagnostic.

  Only the 3-argument form is rewritten: `String.replace/4` options are not
  `Regex.replace/4` options (`:insert_replaced` has no counterpart), so an
  options list is left alone.

  The Pattern round has a sibling rule (`Credence.Pattern.NoMultiArityFnInStringReplace`)
  for the same mistake, but its fix pass only runs on source that compiles. This
  rule covers the case the sibling cannot reach: a `String.replace` evaluated at
  compile time (a module attribute, a macro body), where the `FunctionClauseError`
  aborts compilation.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "no function clause matching in String.replace"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

  @doc """
  Only report when `fix/2` would actually rewrite the source.

  Every failed `String.replace` guard produces the same message — a non-binary
  subject, a bad pattern, a multi-arity replacement — and this rule only fixes
  the last of those, and only for a regex literal.
  """
  def should_report?(diagnostic, source), do: fix(source, diagnostic) != source

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_string_replace_arity_mismatch,
      message:
        "String.replace/3 requires a 1-arity function; use Regex.replace/3 for multi-arity callbacks with captures",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          # String.replace(str, ~r/…/, fn a, b, c -> ... end)
          # → Regex.replace(~r/…/, str, fn a, b, c -> ... end)
          {{:., dot_meta, [{:__aliases__, alias_meta, [:String]}, :replace]}, call_meta,
           [str, pattern, {:fn, _, _} = replacement]} = node,
          acc ->
            if regex_literal?(pattern) and multi_arity_fn?(replacement) do
              {{{:., dot_meta, [{:__aliases__, alias_meta, [:Regex]}, :replace]}, call_meta,
                [pattern, str, replacement]}, true}
            else
              {node, acc}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  defp regex_literal?({sigil, _meta, [{:<<>>, _, _}, modifiers]})
       when sigil in [:sigil_r, :sigil_R] and is_list(modifiers),
       do: true

  defp regex_literal?(_), do: false

  defp multi_arity_fn?({:fn, _, clauses}) when is_list(clauses) do
    Enum.any?(clauses, fn
      # A guarded clause wraps its params in a `:when` node whose args are
      # the params followed by the guard expression.
      {:->, _, [[{:when, _, when_args}], _]} when length(when_args) >= 3 -> true
      {:->, _, [params, _]} when length(params) >= 2 -> true
      _ -> false
    end)
  end

  defp multi_arity_fn?(_), do: false

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
