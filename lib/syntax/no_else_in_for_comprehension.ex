defmodule Credence.Syntax.NoElseInForComprehension do
  @moduledoc """
  Detects and removes the unsupported `else` clause in `for` comprehensions.

  LLMs (especially those translating from Python) write `for ... do ... else ... end`,
  which Elixir parses but rejects at compile time with
  "unsupported option :else given to for". Removing the `else` clause repairs the
  syntax; the `else` body is dead code in Python semantics (it fires only when the
  loop completes without `break`, which Elixir comprehensions don't have).

  ## Bad (won't compile)

      for x <- [1, 2, 3] do
        x * 2
      else
        _ -> []
      end

  ## Good

      for x <- [1, 2, 3] do
        x * 2
      end
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @impl true
  def analyze(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {_ast, issues} =
          Macro.prewalk(ast, [], fn
            {:for, _for_meta, [_generators, opts]} = node, acc when is_list(opts) ->
              case find_else_option(opts) do
                {{:__block__, else_meta, [:else]}, _body} ->
                  issue = %Issue{
                    rule: :no_else_in_for_comprehension,
                    message: "`else` is not supported in `for` — remove it",
                    meta: %{line: else_meta[:line]}
                  }

                  {node, [issue | acc]}

                nil ->
                  {node, acc}
              end

            node, acc ->
              {node, acc}
          end)

        Enum.reverse(issues)

      _ ->
        []
    end
  end

  @impl true
  def fix(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        ranges = collect_else_ranges(ast)

        case ranges do
          [] ->
            source

          ranges ->
            lines = String.split(source, "\n")

            # Process in reverse order so line numbers remain stable.
            sorted = Enum.sort_by(ranges, & &1.else_line, :desc)

            fixed_lines =
              Enum.reduce(sorted, lines, fn %{else_line: else_line, end_line: end_line}, acc ->
                # Remove lines from else_line to end_line - 1 (inclusive).
                # The end_line itself (the for's `end`) is kept.
                remove_from = else_line - 1
                remove_to = end_line - 2

                Enum.take(acc, remove_from) ++ Enum.drop(acc, remove_to + 1)
              end)

            Enum.join(fixed_lines, "\n")
        end

      _ ->
        source
    end
  end

  defp find_else_option(opts) do
    Enum.find(opts, fn
      {{:__block__, _, [:else]}, _} -> true
      _ -> false
    end)
  end

  defp collect_else_ranges(ast) do
    {_ast, ranges} =
      Macro.prewalk(ast, [], fn
        {:for, for_meta, [_generators, opts]} = node, acc when is_list(opts) ->
          case find_else_option(opts) do
            {{:__block__, else_meta, [:else]}, _body} ->
              range = %{
                else_line: else_meta[:line],
                end_line: for_meta[:end][:line]
              }

              {node, [range | acc]}

            nil ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    ranges
  end
end
