defmodule Credence.Pattern.NoDefensiveTypeGuardClause do
  @moduledoc """
  Detects function clauses whose guard is solely a negated type-check
  (e.g. `when not is_integer(n)`) and removes them.

  Such "defensive" guards silently swallow contract violations that the
  `@spec` already rules out. Removing the clause lets Elixir crash on
  bad input per the "let it crash" philosophy, while preserving identical
  behaviour for all spec-conformant inputs.

  ## Bad

      @spec check_power_of_two(integer()) :: boolean()
      def check_power_of_two(n) when not is_integer(n) do
        false
      end

      def check_power_of_two(n) when n <= 0 do
        false
      end

      def check_power_of_two(n) do
        Bitwise.band(n, n - 1) == 0
      end

  ## Good

      @spec check_power_of_two(integer()) :: boolean()
      def check_power_of_two(n) when n <= 0 do
        false
      end

      def check_power_of_two(n) do
        Bitwise.band(n, n - 1) == 0
      end

  ## Flagged patterns

  A `def`/`defp` clause whose guard is `when not <type_check>(var)` where
  `<type_check>` is one of the Kernel type guards (`is_integer`, `is_binary`,
  `is_list`, `is_atom`, `is_float`, `is_number`, `is_bitstring`, `is_map`,
  `is_tuple`, `is_function`, `is_pid`, `is_port`, `is_reference`,
  `is_boolean`, `is_nil`).

  Only guards that are **solely** the negated type check are flagged —
  compound guards (e.g. `when not is_integer(n) and n > 0`) are left alone.
  """
  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  # Kernel type-check guards
  @type_guards ~w(
    is_integer is_binary is_list is_atom is_float is_number
    is_bitstring is_map is_tuple is_function is_pid is_port
    is_reference is_boolean is_nil
  )a |> MapSet.new()

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {def_type, meta, [{:when, _when_meta, [_head, guard]}, _body | _]} = node, acc
        when def_type in [:def, :defp] ->
          if negated_type_guard_only?(guard) do
            {node, [build_issue(meta, def_type, guard) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.get(opts, :source) || Sourceror.to_string(ast)

    RuleHelpers.patches_from_ast_transform(ast, source, fn ast ->
      Macro.prewalk(ast, fn
        {:__block__, meta, stmts} when is_list(stmts) ->
          {:__block__, meta, remove_defensive_clauses(stmts)}

        node ->
          node
      end)
    end)
  end

  # Check if a guard is solely a negated type check: `not is_integer(n)`
  defp negated_type_guard_only?({:not, _, [{guard_name, _, [_arg]}]})
       when is_atom(guard_name) do
    guard_name in @type_guards
  end

  defp negated_type_guard_only?(_), do: false

  # Remove def/defp clauses whose guard is a negated type check
  defp remove_defensive_clauses(stmts) do
    Enum.reject(stmts, fn
      {def_type, _meta, [{:when, _when_meta, [_head, guard]}, _body | _]}
      when def_type in [:def, :defp] ->
        negated_type_guard_only?(guard)

      _ ->
        false
    end)
  end

  defp build_issue(meta, def_type, guard) do
    guard_str = Sourceror.to_string(guard)

    %Issue{
      rule: :no_defensive_type_guard_clause,
      message:
        "Defensive type-guard clause `#{def_type} ... when #{guard_str}` " <>
          "silently swallows spec violations. Remove this clause and let " <>
          "Elixir crash on bad input per \"let it crash\".",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
