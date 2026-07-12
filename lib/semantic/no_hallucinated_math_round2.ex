defmodule Credence.Semantic.NoHallucinatedMathRound2 do
  @moduledoc """
  Fixes the compile error caused by calling `:math.round/1`.

  LLMs frequently hallucinate `:math.round/1` — Erlang's `:math` module has
  `ceil/1` and `floor/1` but no `round/1`. The compiler emits:

      ":math.round/1 is undefined or private"

  The correct Elixir equivalent is `Kernel.round/1`, auto-imported as `round/1`.
  This rule replaces `:math.round(x)` with `round(x)`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_pattern ~r/:math\.round\/1 is undefined or private/

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    Regex.match?(@match_pattern, msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_hallucinated_math_round2,
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
