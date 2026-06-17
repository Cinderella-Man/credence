defmodule Credence.Pattern.NoRedundantAssignment do
  @moduledoc """
  Detects a single plain variable being assigned and immediately returned as
  the last two statements of a block.

  This is a common verbosity pattern where the assignment adds no value. In
  Elixir, the last expression in a block is its return value, so the
  intermediate binding is unnecessary.

  ## Example

      # Bad
      result = compute(x)
      result

      # Good
      compute(x)

  Only a single plain variable is fixed. Tuple/list patterns (`{a, b} =
  process(input); {a, b}`) are left alone: collapsing them would discard the
  match's implicit arity assertion, so the rewrite would not be strictly
  behavior-preserving.

  ## Auto-fix

  Replaces the last two statements with just the RHS of the assignment.
  """

  use Credence.Pattern.Rule
  alias Credence.{Issue, RuleHelpers}

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:__block__, _meta, statements} = node, acc when is_list(statements) ->
          case check_last_pair(statements) do
            {:flag, issue} -> {node, [issue | acc]}
            :clean -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, &maybe_rewrite_block/1)
  end

  # Checks if the last two statements in a block form a redundant
  # assign-and-return pattern.
  defp check_last_pair(statements) when length(statements) >= 2 do
    second_to_last = Enum.at(statements, -2)
    last = Enum.at(statements, -1)

    case second_to_last do
      {:=, meta, [lhs, _rhs]} ->
        if fixable_pattern?(lhs) and structurally_identical?(lhs, last) do
          {:flag, build_issue(meta)}
        else
          :clean
        end

      _ ->
        :clean
    end
  end

  defp check_last_pair(_), do: :clean

  # Only a single plain variable is fixable. The tuple/list forms
  # (`{a, b} = f(); {a, b}` -> `f()`) were dropped: collapsing them discards the
  # implicit arity assertion of the match, so the rewrite is not strictly
  # behavior-preserving (it would no longer raise on a wrong-shaped return).
  defp fixable_pattern?({:__block__, _, [inner]}), do: fixable_pattern?(inner)

  defp fixable_pattern?({name, _, ctx}) when is_atom(name) and is_atom(ctx) and name != :_,
    do: true

  defp fixable_pattern?(_), do: false

  # Two AST nodes are structurally identical if they represent the
  # same source code, ignoring position metadata. Using Macro.to_string
  # as the normalizer handles all AST representation differences
  # (2-tuples vs {:{}, _, _}, __block__ wrapping, cons cells, etc).
  defp structurally_identical?(a, b) do
    Macro.to_string(a) == Macro.to_string(b)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_redundant_assignment,
      message:
        "Variable is assigned and immediately returned. " <>
          "The assignment is redundant — return the expression directly.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  # Postwalk callback: rewrites a __block__ if its last two statements
  # form a redundant assign-and-return.
  defp maybe_rewrite_block({:__block__, meta, statements} = node)
       when is_list(statements) and length(statements) >= 2 do
    second_to_last = Enum.at(statements, -2)
    last = Enum.at(statements, -1)

    case second_to_last do
      {:=, _, [lhs, rhs]} ->
        if fixable_pattern?(lhs) and structurally_identical?(lhs, last) do
          {preceding, _last_two} = Enum.split(statements, length(statements) - 2)
          {:__block__, meta, preceding ++ [preserve_comments(rhs, second_to_last, last)]}
        else
          node
        end

      _ ->
        node
    end
  end

  defp maybe_rewrite_block(node), do: node

  # The assignment (lhs + `=`) and the trailing variable are both discarded; any
  # comment that sat on them (e.g. a `# why` line before the assignment) must
  # land on the surviving rhs so the fix never silently drops it.
  defp preserve_comments(rhs, {:=, assign_meta, [lhs, _rhs]}, last) do
    before = Keyword.get(assign_meta, :leading_comments, []) ++ RuleHelpers.collect_comments(lhs)

    after_ =
      Keyword.get(assign_meta, :trailing_comments, []) ++ RuleHelpers.collect_comments(last)

    RuleHelpers.carry_comments(rhs, before, after_)
  end
end
