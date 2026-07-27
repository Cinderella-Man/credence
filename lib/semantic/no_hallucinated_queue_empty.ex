defmodule Credence.Semantic.NoHallucinatedQueueEmpty do
  @moduledoc """
  Fixes the LLM hallucination of `:queue.empty/0` — a function that does not
  exist in Erlang's `:queue` module.

  LLMs frequently generate `:queue.empty()` when they intend to create a new
  empty queue. The correct zero-arity constructor is `:queue.new()`. The
  compiler emits:

      :queue.empty/0 is undefined or private. Did you mean:

          * is_empty/1

  The fix is deterministic: any call to `:queue.empty()` is replaced with
  `:queue.new()`. The rewrite preserves arity (both are zero-arity) and
  type (`:queue.new/0` returns an empty queue, same as the intended behaviour
  of the hallucinated `:queue.empty/0`).
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_fragment ":queue.empty/0 is undefined"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_fragment)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_hallucinated_queue_empty,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {{:., meta, [{:__block__, bmeta, [:queue]}, :empty]}, call_meta, args}, _acc ->
            {{{:., meta, [{:__block__, bmeta, [:queue]}, :new]}, call_meta, args}, true}

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
