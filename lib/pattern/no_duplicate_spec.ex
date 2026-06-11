defmodule Credence.Pattern.NoDuplicateSpec do
  @moduledoc """
  Detects duplicate `@spec` annotations before function clauses.

  In Elixir, `@spec` is a compile-time type annotation consumed by tools like
  Dialyzer — it has zero runtime effect. Writing the same `@spec` before every
  clause of a function is redundant noise: the compiler only needs one. This
  rule flags the duplicates and removes them, keeping the first `@spec` per
  function name.

  ## Bad

      @spec largest_square_number(non_neg_integer()) :: non_neg_integer()
      def largest_square_number(0), do: 0

      @spec largest_square_number(non_neg_integer()) :: non_neg_integer()
      def largest_square_number(number) when is_integer(number) and number >= 0 do
        root = floor(:math.sqrt(number))
        root * root
      end

  ## Good

      @spec largest_square_number(non_neg_integer()) :: non_neg_integer()
      def largest_square_number(0), do: 0

      def largest_square_number(number) when is_integer(number) and number >= 0 do
        root = floor(:math.sqrt(number))
        root * root
      end
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:__block__, _, stmts} = node, acc when is_list(stmts) ->
          new_issues = detect_duplicate_specs(stmts) ++ acc
          {node, new_issues}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_ast_transform(ast, "", fn ast ->
      Macro.prewalk(ast, fn
        {:__block__, meta, stmts} when is_list(stmts) ->
          {:__block__, meta, strip_duplicate_specs(stmts)}

        node ->
          node
      end)
    end)
  end

  # Walk the statement list and flag @spec annotations that are duplicates.
  # A @spec is a duplicate if the same function name already had a @spec
  # earlier in the same block, before the function definition was reached.
  defp detect_duplicate_specs(stmts) do
    {_, issues} =
      Enum.reduce(stmts, {MapSet.new(), []}, fn
        {:@, _, [{:spec, _, _}]} = node, {seen, issues} ->
          case extract_spec_fun_name(node) do
            nil ->
              {seen, issues}

            name ->
              if MapSet.member?(seen, name) do
                issue = build_issue(elem(node, 1), name)
                {seen, [issue | issues]}
              else
                {MapSet.put(seen, name), issues}
              end
          end

        {dt, _, _} = def_node, {seen, issues} when dt in [:def, :defp] ->
          # A function definition resets the seen set — clauses of the same
          # function are normal, but a new @spec for a *different* function
          # should not be blocked by an earlier function's spec.
          name = extract_def_fun_name(def_node)

          if name do
            {MapSet.put(seen, name), issues}
          else
            {seen, issues}
          end

        _node, acc ->
          acc
      end)

    issues
  end

  # Walk the statement list and remove @spec annotations that are duplicates,
  # keeping only the first @spec per function name.
  defp strip_duplicate_specs(stmts) do
    {_, filtered} =
      Enum.reduce(stmts, {MapSet.new(), []}, fn
        {:@, _, [{:spec, _, _}]} = node, {seen, acc} ->
          case extract_spec_fun_name(node) do
            nil ->
              {seen, [node | acc]}

            name ->
              if MapSet.member?(seen, name) do
                # Duplicate — drop it
                {seen, acc}
              else
                {MapSet.put(seen, name), [node | acc]}
              end
          end

        {dt, _, _} = def_node, {seen, acc} when dt in [:def, :defp] ->
          name = extract_def_fun_name(def_node)

          if name do
            {MapSet.put(seen, name), [def_node | acc]}
          else
            {seen, [def_node | acc]}
          end

        node, {seen, acc} ->
          {seen, [node | acc]}
      end)

    Enum.reverse(filtered)
  end

  # Extract the function name from a @spec annotation.
  # @spec foo(args) :: return  =>  :foo
  # @spec foo(args) :: return when constraints  =>  :foo
  defp extract_spec_fun_name({:@, _, [{:spec, _, [spec_expr]}]}) do
    extract_fun_from_spec(spec_expr)
  end

  defp extract_spec_fun_name(_), do: nil

  # Handle the :: with optional when clause
  defp extract_fun_from_spec({:when, _, [spec_expr, _constraints]}) do
    extract_fun_from_spec(spec_expr)
  end

  defp extract_fun_from_spec({:"::", _, [{name, _, _} | _]}) when is_atom(name), do: name
  defp extract_fun_from_spec(_), do: nil

  # Extract the function name from a def/defp head (handles guards).
  defp extract_def_fun_name({_, _, [{:when, _, [{name, _, _} | _]} | _]})
       when is_atom(name),
       do: name

  defp extract_def_fun_name({_, _, [{name, _, _} | _]}) when is_atom(name), do: name
  defp extract_def_fun_name(_), do: nil

  defp build_issue(meta, name) do
    %Issue{
      rule: :no_duplicate_spec,
      message:
        "Duplicate `@spec` for `#{name}`. " <>
          "`@spec` is a compile-time annotation; the second one is redundant and should be removed.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
