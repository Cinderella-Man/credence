defmodule Credence.Semantic.NoHallucinatedMathFn do
  @moduledoc """
  Fixes the compile error caused by calling `:math.min/2` or `:math.max/2`.

  LLMs frequently hallucinate `:math.min/2` and `:math.max/2` from Python's
  math module — Erlang's `:math` module (trig/float helpers) has neither.
  The compiler emits a warning like:

      ":math.min/2 is undefined or private"

  The existing `UndefinedFunction` rule detects the diagnostic but cannot fix
  it (the function is not in its replacement maps). This targeted semantic
  rule replaces the nonexistent `:math.min`/`:math.max` calls with
  `Kernel.min`/`Kernel.max`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_pattern ~r/:math\.(min|max)\/2 is undefined or private/

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    Regex.match?(@match_pattern, msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_hallucinated_math_fn,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {{:., dot_meta, [{:__block__, block_meta, [:math]}, fun]}, call_meta, args}, _acc
          when fun in [:min, :max] ->
            new_alias = {:__aliases__, [line: dot_meta[:line] || block_meta[:line]], [:Kernel]}
            {{{:., dot_meta, [new_alias, fun]}, call_meta, args}, true}

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
