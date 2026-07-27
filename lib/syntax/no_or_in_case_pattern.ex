defmodule Credence.Syntax.NoOrInCasePattern do
  @moduledoc """
  Detects and repairs `case` clauses that use `or` in patterns.

  `or` is not valid inside a case pattern — the compiler rejects it with
  "invalid expression in match". LLMs sometimes write `nil or "" -> :empty`
  when they mean separate clauses.

  The deterministic fix splits the `or` pattern into individual clauses,
  each with the same body:

  ## Bad (compile error)

      case val do
        nil or "" -> :empty
        _ -> :ok
      end

  ## Good

      case val do
        nil -> :empty
        "" -> :empty
        _ -> :ok
      end

  Handles nested `or` (`a or b or c`) recursively.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @impl true
  def analyze(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {_ast, issues} =
          Macro.prewalk(ast, [], fn
            {:case, _meta, [_subject, opts]} = node, acc when is_list(opts) ->
              case_issues =
                opts
                |> extract_case_clauses()
                |> Enum.flat_map(fn clause ->
                  case clause do
                    {:->, _, [patterns, _body]} ->
                      patterns
                      |> Enum.filter(&or_pattern?/1)
                      |> Enum.map(fn {:or, or_meta, _} ->
                        %Issue{
                          rule: :no_or_in_case_pattern,
                          message: "`or` in case pattern — split into separate clauses",
                          meta: %{line: or_meta[:line]}
                        }
                      end)

                    _ ->
                      []
                  end
                end)

              {node, acc ++ case_issues}

            node, acc ->
              {node, acc}
          end)

        issues

      _ ->
        []
    end
  end

  @impl true
  def fix(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        transformed =
          Macro.prewalk(ast, fn
            {:case, case_meta, [subject, [{{:__block__, do_meta, [:do]}, clauses}]]} ->
              new_clauses =
                Enum.flat_map(clauses, fn
                  {:->, clause_meta, [patterns, body]} = clause ->
                    or_patterns = Enum.filter(patterns, &or_pattern?/1)

                    case or_patterns do
                      [] ->
                        [clause]

                      _ ->
                        all_operands = Enum.flat_map(or_patterns, &collect_or_operands/1)
                        other_patterns = Enum.reject(patterns, &or_pattern?/1)

                        Enum.map(all_operands, fn operand ->
                          {:->, clause_meta, [[operand | other_patterns], body]}
                        end)
                    end

                  other ->
                    [other]
                end)

              {:case, case_meta, [subject, [{{:__block__, do_meta, [:do]}, new_clauses}]]}

            node ->
              node
          end)

        if transformed == ast do
          source
        else
          Sourceror.to_string(transformed)
        end

      _ ->
        source
    end
  end

  defp extract_case_clauses(opts) when is_list(opts) do
    case Enum.find(opts, &do_block?/1) do
      {{:__block__, _, [:do]}, clauses} when is_list(clauses) -> clauses
      _ -> []
    end
  end

  defp extract_case_clauses(_), do: []

  defp do_block?({{:__block__, _, [:do]}, _}), do: true
  defp do_block?(_), do: false

  defp or_pattern?({:or, _, [_, _]}), do: true
  defp or_pattern?(_), do: false

  defp collect_or_operands({:or, _, [left, right]}),
    do: collect_or_operands(left) ++ collect_or_operands(right)

  defp collect_or_operands(other), do: [other]
end
