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

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Named functions: def / defp
        {kind, meta, [{_name, _, args}, _body]} = node, issues
        when kind in [:def, :defp] ->
          found_names = find_short_params(args || [], [])
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

  defp find_short_params(args, acc) when is_list(args) do
    Enum.reduce(args, acc, &find_short_params/2)
  end

  defp find_short_params({name, _meta, context}, acc) when is_atom(name) and is_atom(context) do
    str_name = Atom.to_string(name)

    if String.length(str_name) == 1 and str_name != "_" do
      [str_name | acc]
    else
      acc
    end
  end

  defp find_short_params({_name, _meta, args}, acc) when is_list(args) do
    find_short_params(args, acc)
  end

  defp find_short_params({left, right}, acc) do
    acc = find_short_params(left, acc)
    find_short_params(right, acc)
  end

  defp find_short_params(_, acc), do: acc

  defp format_issues(names, meta) do
    names
    |> Enum.uniq()
    |> Enum.map(fn name ->
      %Issue{
        rule: :descriptive_names,
        message: "The parameter `#{name}` is a single letter. Use a more descriptive name.",
        meta: %{line: Keyword.get(meta, :line)}
      }
    end)
  end
end
