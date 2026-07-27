defmodule Credence.Semantic.FixHallucinatedStreamDataFlatMap do
  @moduledoc """
  Fixes compile errors caused by LLM-hallucinated `StreamData.flat_map/2`.

  LLMs repeatedly hallucinate this function; it does not exist in StreamData.
  The compiler emits:

      "function StreamData.flat_map/2 is undefined or private"

  The existing `undefined_function` rule matches the diagnostic but returns
  identical source (no fix), causing repeated compile failures.

  The fix replaces `StreamData.flat_map/2` with `StreamData.bind/2`, which
  is the actual monadic bind in StreamData — the correct equivalent.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, "flat_map") and String.contains?(msg, "StreamData")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_hallucinated_stream_data_flat_map,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed?} =
        Macro.prewalk(ast, false, fn
          {{:., dot_meta, [{:__aliases__, mod_meta, [:StreamData]}, :flat_map]}, call_meta, args},
          _acc ->
            {{{:., dot_meta, [{:__aliases__, mod_meta, [:StreamData]}, :bind]}, call_meta, args},
             true}

          node, acc ->
            {node, acc}
        end)

      if changed?, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
