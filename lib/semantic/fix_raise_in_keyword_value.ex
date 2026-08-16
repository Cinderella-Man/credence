defmodule Credence.Semantic.FixRaiseInKeywordValue do
  @moduledoc """
  Fixes bare `raise` calls in `do:` keyword values that lack parentheses.

  LLMs write `def f(args), do: raise ErrorType, "msg"` which triggers the
  compiler warning:

      missing parentheses for expression following "do:" keyword.
      Parentheses are required to solve ambiguity inside keywords.

  Under `--warnings-as-errors` this blocks compilation. The fix wraps the
  `raise` call in parentheses, resolving the ambiguity deterministically:

      def f(args), do: raise(ErrorType, "msg")

  The rewrite only targets `raise` calls that are the direct value of a
  `do:` keyword (not `do...end` blocks) and that lack closing-paren
  metadata — so already-parenthesised calls are left untouched.

  ## Bad

      defmodule CredenceRaiseInKeywordLiveRepro do
        def f(_, _), do: raise ArgumentError, "bad argument"
      end

  ## Good

      defmodule CredenceRaiseInKeywordLiveRepro do
        def f(_, _), do: raise(ArgumentError, "bad argument")
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "missing parentheses for expression following"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

  @doc """
  Only report diagnostics the fix will actually rewrite. The same
  "missing parentheses" warning fires for any unparenthesised call inside
  a keyword (e.g. `foo x, bar: 1` or a bare `if`), but this rule only
  parenthesises bare `raise` calls in `do:` keyword values — so a source
  the fix leaves untouched must not be flagged.
  """
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_raise_in_keyword_value,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {{:__block__, kw_meta, [:do]}, {:raise, raise_meta, [_ | _] = args}}, acc
          when is_list(kw_meta) ->
            # Only fix bare raise in `do:` keyword values (not `do...end` blocks)
            if Keyword.get(kw_meta, :format) == :keyword and
                 not Keyword.has_key?(raise_meta, :closing) do
              case Sourceror.get_range({:raise, raise_meta, args}) do
                %Sourceror.Range{end: end_pos} ->
                  new_meta =
                    Keyword.put(raise_meta, :closing,
                      line: end_pos[:line],
                      column: end_pos[:column]
                    )

                  {{{:__block__, kw_meta, [:do]}, {:raise, new_meta, args}}, true}

                _ ->
                  {{{:__block__, kw_meta, [:do]}, {:raise, raise_meta, args}}, acc}
              end
            else
              {{{:__block__, kw_meta, [:do]}, {:raise, raise_meta, args}}, acc}
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
