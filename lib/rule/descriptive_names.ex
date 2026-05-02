defmodule Credence.Rule.DescriptiveNames do
  @moduledoc """
  Maintainability rule: Detects single-letter variable names in function signatures.

  Using single-letter names like `a`, `x`, or `n` forces the reader to keep track
  of the variable's purpose in their short-term memory. Replacing these with
  descriptive names reduces cognitive load and makes the code self-documenting.

  While common in mathematical contexts, in software development, explicit names
  like `index`, `accumulator`, or `user_id` make the logic much easier to reason
  about at a glance.

  ## Bad

      # Named functions
      def handle_event(e, s), do: {:ok, s}

      # Anonymous functions
      Enum.reduce(list, 0, fn x, acc -> x + acc end)

  ## Good

      # Named functions
      def handle_event(event, state), do: {:ok, state}

      # Anonymous functions
      Enum.reduce(list, 0, fn price, total_sum -> price + total_sum end)

      # Single underscores (ignored by this rule)
      def handle_call(_msg, _from, state), do: {:reply, :ok, state}
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
