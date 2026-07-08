defmodule Credence.Semantic.FixUnmatchableTupleDestructure do
  @moduledoc """
  Fixes compiler errors caused by LLMs destructuring an integer as a tuple.

  LLMs (especially Qwen) frequently hallucinate patterns like:

      {var, _} = DateTime.to_unix(DateTime.utc_now(), :microsecond)

  This attempts to destructure an integer (the return value of DateTime.to_unix/2)
  as a 2-tuple, which crashes on every input with MatchError. The compiler emits
  "misplaced operator |/2" when it encounters this unmatchable pattern.

  The fix replaces the impossible tuple destructure with a simple assignment:

      {var, _} = expr  →  var = expr
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "misplaced operator |/2"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_unmatchable_tuple_destructure,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {result, changed?} =
          Macro.prewalk(ast, false, fn
            {:=, assign_meta,
             [
               {:__block__, _, [{{:_, _, _}, {var_name, _, nil} = var}]},
               rhs
             ]} = _node,
            _acc
            when is_atom(var_name) and var_name != :_ ->
              # {_, var} = expr  →  var = expr
              {{:=, assign_meta, [var, rhs]}, true}

            {:=, assign_meta,
             [
               {:__block__, _, [{{var_name, _, nil} = var, {:_, _, _}}]},
               rhs
             ]} = _node,
            _acc
            when is_atom(var_name) and var_name != :_ ->
              # {var, _} = expr  →  var = expr
              {{:=, assign_meta, [var, rhs]}, true}

            node, acc ->
              {node, acc}
          end)

        if changed?, do: Sourceror.to_string(result), else: source

      _ ->
        source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
