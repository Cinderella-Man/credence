defmodule Credence.Semantic.NoOrInCasePattern do
  @moduledoc """
  Fixes `or` patterns in `case` clauses that cause compile-time errors.

  LLMs write `or` in case patterns (e.g. `nil or ""`) to express "match
  either", but `Kernel.or/2` rejects pattern context with:

      invalid expression in match, or is not allowed in patterns

  The deterministic fix splits the `or` clause into separate clauses, each
  carrying the original body:

      # Before
      case value do
        nil or "" -> :empty
        _ -> :present
      end

      # After
      case value do
        nil -> :empty
        "" -> :empty
        _ -> :present
      end

  ## Bad

      defmodule Example do
        def classify(value) do
          case value do
            nil or "" -> :empty
            _ -> :present
          end
        end
      end

  ## Good

      defmodule Example do
        def classify(value) do
          case value do
            nil -> :empty
            "" -> :empty
            _ -> :present
          end
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "or is not allowed in patterns"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_or_in_case_pattern,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      result =
        Macro.prewalk(ast, fn
          {:case, meta, [subject, clauses_kw]} = node ->
            case split_or_clauses(clauses_kw) do
              {:ok, new_kw} -> {:case, meta, [subject, new_kw]}
              :unchanged -> node
            end

          node ->
            node
        end)

      if result == ast do
        source
      else
        Sourceror.to_string(result)
      end
    else
      _ -> source
    end
  end

  # Walk the case clause keyword list and expand any clause whose pattern
  # contains `or` into multiple clauses.
  defp split_or_clauses(clauses_kw) do
    new_kw =
      Enum.flat_map(clauses_kw, fn
        {{:__block__, do_meta, [:do]}, clause_asts} ->
          {new_clauses, did_change} = expand_or_in_clauses(clause_asts)
          if did_change, do: :erlang.put(:or_changed, true)
          [{{:__block__, do_meta, [:do]}, new_clauses}]

        other ->
          [other]
      end)

    if :erlang.get(:or_changed) == true do
      :erlang.erase(:or_changed)
      {:ok, new_kw}
    else
      :unchanged
    end
  end

  # Expand `or` patterns in a list of clause ASTs.
  defp expand_or_in_clauses(clauses) do
    Enum.reduce(clauses, {[], false}, fn
      {:->, arrow_meta, [[pattern], body]}, {acc, changed} ->
        case collect_patterns(pattern) do
          [_single] ->
            {[{:->, arrow_meta, [[pattern], body]} | acc], changed}

          [_ | _] = patterns ->
            new_clauses =
              Enum.map(patterns, fn p ->
                {:->, arrow_meta, [[p], body]}
              end)

            {Enum.reverse(new_clauses) ++ acc, true}
        end

      clause, {acc, changed} ->
        {[clause | acc], changed}
    end)
    |> then(fn {clauses, changed} -> {Enum.reverse(clauses), changed} end)
  end

  # Collect all leaf patterns from a nested `or` tree.
  # `{:or, _, [left, right]}` → recurse into both sides.
  defp collect_patterns({:or, _meta, [left, right]}) do
    collect_patterns(left) ++ collect_patterns(right)
  end

  defp collect_patterns(pattern), do: [pattern]

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
