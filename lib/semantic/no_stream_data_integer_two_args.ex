defmodule Credence.Semantic.NoStreamDataIntegerTwoArgs do
  @moduledoc """
  Repairs the compiler error when `StreamData.integer/2` is called with two
  separate arguments instead of a single `Range`.

  LLMs (especially Qwen) hallucinate `StreamData.integer(min, max)` matching
  Python's `randint`; `integer/2` does not exist in StreamData — the fix is
  `integer(min..max)`.

  The compiler emits:

      function StreamData.__using__/1 is undefined or private

  because the import of `StreamData` fails when `integer/2` is called.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "StreamData.__using__/1"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_stream_data_integer_two_args,
      message: "StreamData.integer/2 does not exist — use integer(min..max)",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {new_ast, changed} =
          Macro.prewalk(ast, false, fn
            {:integer, meta, [arg1, arg2]}, _acc ->
              range = {:.., [], [arg1, arg2]}
              {{:integer, meta, [range]}, true}

            node, acc ->
              {node, acc}
          end)

        if changed, do: Sourceror.to_string(new_ast), else: source

      _ ->
        source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
