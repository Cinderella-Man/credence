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

      defmodule ExampleNOICP do
        def classify(value) do
          case value do
            nil or "" -> :empty
            _ -> :present
          end
        end
      end

  ## Good

      defmodule ExampleNOICP do
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
        Macro.traverse(ast, 0, &enter_quote/2, &rewrite_pattern_context/2)
        |> elem(0)

      if result == ast do
        source
      else
        Sourceror.to_string(result)
      end
    else
      _ -> source
    end
  end

  defp enter_quote({:quote, _, _} = node, quote_depth), do: {node, quote_depth + 1}
  defp enter_quote(node, quote_depth), do: {node, quote_depth}

  defp rewrite_pattern_context({:quote, _, _} = node, quote_depth),
    do: {node, quote_depth - 1}

  defp rewrite_pattern_context(node, quote_depth) when quote_depth > 0,
    do: {node, quote_depth}

  defp rewrite_pattern_context({:__block__, meta, children}, quote_depth) do
    flattened =
      Enum.flat_map(children, fn
        {:__block__, [generated: true], generated_children} -> generated_children
        child -> [child]
      end)

    {{:__block__, meta, flattened}, quote_depth}
  end

  defp rewrite_pattern_context({:case, meta, [subject, clauses_kw]} = node, quote_depth) do
    case split_or_clauses(clauses_kw) do
      {:ok, new_kw} -> {{:case, meta, [subject, new_kw]}, quote_depth}
      :unchanged -> {node, quote_depth}
    end
  end

  defp rewrite_pattern_context({:fn, meta, clauses} = node, quote_depth) do
    case expand_or_in_clauses(clauses) do
      {new_clauses, true} -> {{:fn, meta, new_clauses}, quote_depth}
      {_clauses, false} -> {node, quote_depth}
    end
  end

  defp rewrite_pattern_context({kind, meta, [head, body]} = node, quote_depth)
       when kind in [:def, :defp] do
    case expand_function_head(head) do
      [_single] ->
        {node, quote_depth}

      heads ->
        {{:__block__, [generated: true], Enum.map(heads, &{kind, meta, [&1, body]})}, quote_depth}
    end
  end

  defp rewrite_pattern_context({:=, meta, [pattern, value]} = node, quote_depth) do
    case expand_pattern(pattern) do
      [_single] ->
        {node, quote_depth}

      patterns ->
        clauses =
          Enum.map(patterns, fn expanded_pattern ->
            result = {:__or_pattern_value__, [generated: true], nil}
            bound_pattern = {:=, [], [expanded_pattern, result]}
            {:->, [], [[bound_pattern], result]}
          end)

        {{:case, meta, [value, [do: clauses]]}, quote_depth}
    end
  end

  defp rewrite_pattern_context(node, quote_depth), do: {node, quote_depth}

  defp expand_function_head({:when, meta, [call | guards]}) do
    Enum.map(expand_function_head(call), &{:when, meta, [&1 | guards]})
  end

  defp expand_function_head({name, meta, args}) when is_atom(name) and is_list(args) do
    args
    |> expand_pattern_list()
    |> Enum.map(&{name, meta, &1})
  end

  defp expand_function_head(head), do: [head]

  # Walk the case clause keyword list and expand any clause whose pattern
  # contains `or` into multiple clauses.
  defp split_or_clauses(clauses_kw) do
    {new_kw, changed} =
      Enum.map_reduce(clauses_kw, false, fn
        {{:__block__, do_meta, [:do]}, clause_asts}, changed ->
          {new_clauses, did_change} = expand_or_in_clauses(clause_asts)
          {{{:__block__, do_meta, [:do]}, new_clauses}, changed or did_change}

        other, changed ->
          {other, changed}
      end)

    if changed, do: {:ok, new_kw}, else: :unchanged
  end

  # Expand `or` patterns in a list of clause ASTs.
  defp expand_or_in_clauses(clauses) do
    Enum.reduce(clauses, {[], false}, fn
      {:->, arrow_meta, [patterns, body]}, {acc, changed} ->
        case expand_pattern_list(patterns) do
          [_single] ->
            {[{:->, arrow_meta, [patterns, body]} | acc], changed}

          [_ | _] = pattern_lists ->
            new_clauses =
              Enum.map(pattern_lists, fn expanded_patterns ->
                {:->, arrow_meta, [expanded_patterns, body]}
              end)

            {Enum.reverse(new_clauses) ++ acc, true}
        end

      clause, {acc, changed} ->
        {[clause | acc], changed}
    end)
    |> then(fn {clauses, changed} -> {Enum.reverse(clauses), changed} end)
  end

  defp expand_pattern({:or, _meta, [left, right]}) do
    expand_pattern(left) ++ expand_pattern(right)
  end

  defp expand_pattern({:when, meta, [pattern | guards]}) do
    Enum.map(expand_pattern(pattern), &{:when, meta, [&1 | guards]})
  end

  defp expand_pattern({form, meta, children}) when is_list(children) do
    children
    |> expand_pattern_list()
    |> Enum.map(&{form, meta, &1})
  end

  defp expand_pattern(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> expand_pattern_list()
    |> Enum.map(&List.to_tuple/1)
  end

  defp expand_pattern(pattern), do: [pattern]

  defp expand_pattern_list(items) do
    Enum.reduce(items, [[]], fn item, combinations ->
      for combination <- combinations, expanded <- expand_pattern(item) do
        combination ++ [expanded]
      end
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
