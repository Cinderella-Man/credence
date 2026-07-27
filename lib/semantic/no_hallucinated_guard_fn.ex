defmodule Credence.Semantic.NoHallucinatedGuardFn do
  @moduledoc """
  Fixes the compile error caused by `is_regex/1` in guard expressions.

  LLMs frequently hallucinate `is_regex/1` as a guard function; it does not
  exist in Elixir and blocks compilation. The compiler emits:

      "cannot find or invoke local is_regex/1 inside a guard. Only macros can
       be invoked inside a guard and they must be defined before their
       invocation. Called as: is_regex(format)"

  The existing `pattern/hallucinated_guard` rule only runs at pattern phase
  (code must already compile), so it never fires on this class of error.
  This semantic-level rule detects `is_regex(x)` in guards and replaces it
  with `is_struct(x, Regex)`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "cannot find or invoke local is_regex/1 inside a guard"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_hallucinated_guard_fn,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:is_regex, meta, args}, _acc ->
            regex_alias = {:__aliases__, [line: meta[:line]], [:Regex]}
            {{:is_struct, meta, args ++ [regex_alias]}, true}

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
