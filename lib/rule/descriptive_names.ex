defmodule Credence.Rule.DescriptiveNames do
  @moduledoc """
  Maintainability rule: Flags single-letter variable names in function signatures.

  Using names like `a`, `b`, or `n` makes the code harder to reason about.
  Replacing them with descriptive names like `index`, `accumulator`, or `previous_value`
  improves readability and reduces cognitive load.

  ## Bad
      def process(a, b), do: a + b

  ## Good
      def process(base_value, increment), do: base_value + increment
  """

  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Named functions: def / defp
        {kind, meta, [{_name, _, args}, _body]} = node, issues
        when kind in [:def, :defp] ->
          found_names = find_short_params(args || [], [])
          # Return the original node so prewalk keeps traversing into the body
          {node, format_issues(found_names, meta) ++ issues}

        # Anonymous functions: fn ... -> ... end
        {:fn, _fn_meta, clauses} = node, issues when is_list(clauses) ->
          found =
            Enum.flat_map(clauses, fn
              {:->, clause_meta, [args, _body]} ->
                names = find_short_params(args || [], [])
                format_issues(names, clause_meta)

              _ ->
                []
            end)

          {node, found ++ issues}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  # Case 1: A list (the argument list itself or pattern matches like [h | t])
  defp find_short_params(args, acc) when is_list(args) do
    Enum.reduce(args, acc, &find_short_params/2)
  end

  # Case 2: A variable (3-tuple where the 3rd element is an atom/nil, e.g., {:x, meta, nil})
  defp find_short_params({name, _meta, context}, acc) when is_atom(name) and is_atom(context) do
    str_name = Atom.to_string(name)

    if String.length(str_name) == 1 and str_name != "_" do
      [str_name | acc]
    else
      acc
    end
  end

  # Case 3: A 3-tuple AST node (e.g., {:+, meta, [args]}) - recurse into the args list
  defp find_short_params({_name, _meta, args}, acc) when is_list(args) do
    find_short_params(args, acc)
  end

  # Case 4: A 2-tuple literal (e.g., {a, b}) - correctly pass the accumulator through
  defp find_short_params({left, right}, acc) do
    acc = find_short_params(left, acc)
    find_short_params(right, acc)
  end

  # Case 5: Catch-all for literals or things we don't care about
  defp find_short_params(_, acc), do: acc

  defp format_issues(names, meta) do
    names
    |> Enum.uniq()
    |> Enum.map(fn name ->
      %Issue{
        rule: :descriptive_names,
        severity: :warning,
        message: "The parameter `#{name}` is a single letter. Use a more descriptive name.",
        meta: %{line: Keyword.get(meta, :line)}
      }
    end)
  end
end
