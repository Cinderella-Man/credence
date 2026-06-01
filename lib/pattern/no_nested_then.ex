defmodule Credence.Pattern.NoNestedThen do
  @moduledoc """
  Detects `then/2` calls whose anonymous function body contains another
  `then/2` call.  Nested `then` closures create unnecessary depth and
  are a common LLM anti-pattern — use variable assignments instead.

  ## Bad

      str1
      |> String.graphemes()
      |> Enum.frequencies()
      |> then(fn freq1 ->
        str2
        |> String.graphemes()
        |> Enum.frequencies()
        |> then(fn freq2 ->
          freq1 == freq2
        end)
      end)

  ## Good

      freq1 = str1 |> String.graphemes() |> Enum.frequencies()
      freq2 = str2 |> String.graphemes() |> Enum.frequencies()
      freq1 == freq2
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case extract_then_body(node) do
          {:ok, meta, body} ->
            if has_nested_then?(body) do
              issue = %Issue{
                rule: :no_nested_then,
                message:
                  "Nested `then/2` calls create unnecessary closure depth. " <>
                    "Use variable assignments instead.",
                meta: %{line: Keyword.get(meta, :line)}
              }

              {node, [issue | acc]}
            else
              {node, acc}
            end

          :error ->
            {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # Direct call: then(value, fn x -> body end)
  defp extract_then_body({:then, meta, [_value, {:fn, _, clauses}]}) do
    extract_body_from_clauses(meta, clauses)
  end

  # Pipe form: |> then(fn x -> body end) — single arg
  defp extract_then_body({:then, meta, [{:fn, _, clauses}]}) do
    extract_body_from_clauses(meta, clauses)
  end

  # Qualified direct call: Kernel.then(value, fn x -> body end)
  defp extract_then_body(
         {{:., _, [{:__aliases__, _, [:Kernel]}, :then]}, meta,
          [_value, {:fn, _, clauses}]}
       ) do
    extract_body_from_clauses(meta, clauses)
  end

  defp extract_then_body(_), do: :error

  defp extract_body_from_clauses(meta, [{:->, _, [[_params], body]}]) do
    {:ok, meta, body}
  end

  defp extract_body_from_clauses(_, _), do: :error

  defp has_nested_then?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:then, _, _} = node, _acc -> {node, true}
        {{:., _, [{:__aliases__, _, [:Kernel]}, :then]}, _, _} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end
end
