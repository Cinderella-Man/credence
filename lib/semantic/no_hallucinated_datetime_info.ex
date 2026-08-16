defmodule Credence.Semantic.NoHallucinatedDatetimeInfo do
  @moduledoc """
  Fixes the compile error caused by calling `DateTime.info?/1`.

  LLMs frequently hallucinate `DateTime.info?/1` as a struct-check function;
  it does not exist in Elixir. The compiler emits:

      "DateTime.info?/1 is undefined or private"

  The deterministic fix replaces the call:

      DateTime.info?(x)  →  match?(%DateTime{}, x)

  ## Bad

      defmodule XNHDI do
        def f(x), do: DateTime.info?(x)
      end

  ## Good

      defmodule XNHDI do
        def f(x), do: match?(%DateTime{}, x)
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "DateTime.info?/1 is undefined or private"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_hallucinated_datetime_info,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {{:., dot_meta, [{:__aliases__, _alias_meta, [:DateTime]}, :info?]}, _call_meta, [arg]},
          _acc ->
            new_call =
              {:match?, [line: dot_meta[:line]],
               [
                 {:%, [line: dot_meta[:line]],
                  [
                    {:__aliases__, [line: dot_meta[:line]], [:DateTime]},
                    {:%{}, [], []}
                  ]},
                 arg
               ]}

            {new_call, true}

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
