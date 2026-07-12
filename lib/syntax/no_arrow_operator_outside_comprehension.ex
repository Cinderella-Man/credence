defmodule Credence.Syntax.NoArrowOperatorOutsideComprehension do
  @moduledoc """
  Detects and fixes `<-` (comprehension/with arrow) used outside `for`/`with` contexts.

  LLMs frequently write `<-` outside `for`/`with` blocks, causing a compile error:
  `undefined function <-/2`. The arrow operator is only valid as a generator inside
  `for` or as a pattern-match clause inside `with`. Outside those contexts it must
  be `=` (plain assignment/match).

  The deterministic fix replaces every standalone `<-` with `=`. This cannot
  over-fire — `<-` is invalid outside `for`/`with` in every case.

  ## Bad (won't compile — undefined function <-/2)

      subscriber <- Process.whereis(subscriber) || subscriber

  ## Good

      subscriber = Process.whereis(subscriber) || subscriber
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @impl true
  def analyze(source) do
    case find_standalone_arrows(source) do
      [] ->
        []

      lines ->
        Enum.map(lines, fn line ->
          %Issue{
            rule: :no_arrow_operator_outside_comprehension,
            message: "`<-` outside `for`/`with` — use `=` for assignment",
            meta: %{line: line}
          }
        end)
    end
  end

  @impl true
  def fix(source) do
    case find_standalone_arrows(source) do
      [] ->
        source

      lines ->
        lines_set = MapSet.new(lines)

        source
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.map_join("\n", fn {line, line_no} ->
          if line_no in lines_set do
            String.replace(line, ~r/<-\s/, "= ")
          else
            line
          end
        end)
    end
  end

  # Parse the source and find line numbers where `<-` appears outside of
  # `for`/`with` comprehension contexts.
  defp find_standalone_arrows(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        all_arrow_lines = find_all_arrows(ast)
        comprehension_arrow_lines = find_comprehension_arrows(ast)
        comprehension_set = MapSet.new(comprehension_arrow_lines)
        Enum.reject(all_arrow_lines, &(&1 in comprehension_set))

      _ ->
        []
    end
  end

  # Walk the AST and collect line numbers of every `<-` node.
  defp find_all_arrows(ast) do
    {_ast, lines} =
      Macro.prewalk(ast, [], fn
        {:<-, meta, _args} = node, acc ->
          {node, [Keyword.get(meta, :line) | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(lines)
  end

  # Walk the AST and collect line numbers of `<-` nodes that appear as direct
  # children of `for` or `with` nodes (valid comprehension contexts).
  defp find_comprehension_arrows(ast) do
    {_ast, lines} =
      Macro.prewalk(ast, [], fn
        {:for, _meta, args} = node, acc when is_list(args) ->
          arrows = child_arrow_lines(args)
          {node, arrows ++ acc}

        {:with, _meta, args} = node, acc when is_list(args) ->
          arrows = child_arrow_lines(args)
          {node, arrows ++ acc}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(lines)
  end

  # Extract line numbers from `<-` nodes that are direct children of a for/with
  # argument list. This handles multi-line generators.
  defp child_arrow_lines(args) do
    Enum.flat_map(args, fn
      {:<-, meta, _inner_args} ->
        [Keyword.get(meta, :line)]

      _ ->
        []
    end)
  end
end
