defmodule Credence.Semantic.NoStringReplaceArityMismatch do
  @moduledoc """
  Fixes `String.replace/3` calls where a multi-arity anonymous function is
  passed as the replacement for a regex with capture groups.

  LLMs (familiar with Erlang's `re:replace/4`) write multi-arity callbacks:

      String.replace(str, ~r/(a)(b)/, fn full, cap1, cap2 -> ... end)

  `String.replace/3` requires `is_function(replacement, 1)` — only 1-arity
  functions. `Regex.replace/3`, however, calls the function with the full match
  and each capture group as separate arguments, matching the multi-arity
  signature the LLM intended.

  The fix rewrites `String.replace(str, regex, fn ...)` to
  `Regex.replace(regex, str, fn ...)`, preserving the callback arity and body
  verbatim.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "no function clause matching in String.replace"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

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
          # String.replace(str, regex, fn a, b, c -> ... end)
          # → Regex.replace(regex, str, fn a, b, c -> ... end)
          {{:., dot_meta, [{:__aliases__, _alias_meta, [:String]}, :replace]}, call_meta, args},
          _acc
          when is_list(args) and length(args) >= 3 ->
            [str, regex, replacement | rest] = args

            case replacement do
              {:fn, _fn_meta, [{:->, _arrow_meta, [params, _body]}]}
              when is_list(params) and length(params) > 1 ->
                # Rewrite: String.replace(str, regex, fn ...) → Regex.replace(regex, str, fn ...)
                new_args = [regex, str, replacement | rest]

                new_node =
                  {{:., dot_meta, [{:__aliases__, [], [:Regex]}, :replace]}, call_meta, new_args}

                {new_node, true}

              _ ->
                {
                  {{:., dot_meta, [{:__aliases__, [], [:String]}, :replace]}, call_meta, args},
                  false
                }
            end

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
