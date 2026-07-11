defmodule Credence.Semantic.NoHallucinatedMathRound do
  @moduledoc """
  Fixes the compile error caused by calling `:math.round/1`.

  LLMs frequently hallucinate `:math.round/1` — it does not exist in Erlang's
  `:math` module. The compiler parses `:math.round(x)` as the `::/2` type
  operator applied to `:math` and `round(...)`, emitting:

      "misplaced operator ::/2"

  The correct function is `Kernel.round/1`. This rule replaces
  `:math.round(x)` with `round(x)`, which is always correct since `round/1`
  returns an integer identically to what `:math.round/1` would if it existed.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "misplaced operator ::/2"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_hallucinated_math_round,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {{:., dot_meta, [{:__block__, block_meta, [:math]}, :round]}, call_meta, args},
          _acc ->
            line = dot_meta[:line] || block_meta[:line]
            {{:round, [line: line] ++ call_meta, args}, true}

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
