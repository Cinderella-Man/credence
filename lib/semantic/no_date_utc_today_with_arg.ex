defmodule Credence.Semantic.NoDateUtcTodayWithArg do
  @moduledoc """
  Fixes `Date.utc_today(arg)` — the arity-1 form is hallucinated by LLMs.

  `Date.utc_today/0` takes no arguments. LLMs frequently pass a timestamp or
  other argument, producing a call that never matches. The compiler emits:

      "this clause for <fun>/<arity> cannot match because a previous clause
       at line N always matches"

  Stripping the spurious argument makes the call site compile.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "cannot match because a previous clause"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg) and String.contains?(msg, "always matches")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_date_utc_today_with_arg,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {{:., dot_meta, [{:__aliases__, alias_meta, [:Date]}, :utc_today]}, call_meta, [_ | _]},
          _acc ->
            new_node =
              {{:., dot_meta, [{:__aliases__, alias_meta, [:Date]}, :utc_today]}, call_meta, []}

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
