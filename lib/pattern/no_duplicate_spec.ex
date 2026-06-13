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
          case spec_key(node) do
            nil ->
              {seen, issues}

            key ->
              if MapSet.member?(seen, key) do
                {seen, [build_issue(node) | issues]}
              else
                {MapSet.put(seen, key), issues}
              end
          end

        _node, acc ->
          acc
      end)

    issues
  end

  # Walk the statement list and remove @spec annotations that duplicate an
  # earlier identical @spec, keeping the first of each.
  defp strip_duplicate_specs(stmts) do
    {_, filtered} =
      Enum.reduce(stmts, {MapSet.new(), []}, fn
        {:@, _, [{:spec, _, _}]} = node, {seen, acc} ->
          case spec_key(node) do
            nil ->
              {seen, [node | acc]}

            key ->
              if MapSet.member?(seen, key) do
                # Duplicate — drop it
                {seen, acc}
              else
                {MapSet.put(seen, key), [node | acc]}
              end
          end

        node, {seen, acc} ->
          {seen, [node | acc]}
      end)

    Enum.reverse(filtered)
  end

  # Metadata-independent dedup key for a @spec: its full text (name, arity, AND
  # types). Two specs are duplicates only if all three match — distinct
  # overloaded specs for one function (e.g. two `@spec find/2` with different
  # types) are valid and kept.
  defp spec_key({:@, _, [{:spec, _, [spec_expr]}]}), do: Macro.to_string(spec_expr)
  defp spec_key(_), do: nil

  # {name, arity} of a @spec, for the issue message.
  defp spec_name_arity({:@, _, [{:spec, _, [spec_expr]}]}), do: fun_name_arity(spec_expr)
  defp spec_name_arity(_), do: {:unknown, 0}

  defp fun_name_arity({:when, _, [spec_expr, _constraints]}), do: fun_name_arity(spec_expr)

  defp fun_name_arity({:"::", _, [{name, _, args} | _]}) when is_atom(name),
    do: {name, arity(args)}

  defp fun_name_arity(_), do: {:unknown, 0}

  defp arity(args) when is_list(args), do: length(args)
  defp arity(_), do: 0

  defp build_issue(node) do
    {name, arity} = spec_name_arity(node)
    meta = elem(node, 1)
    %Issue{
      rule: :no_duplicate_spec,
      message:
        "Duplicate `@spec` for `#{name}/#{arity}`. " <>
          "`@spec` is a compile-time annotation; the second one is redundant and should be removed.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
