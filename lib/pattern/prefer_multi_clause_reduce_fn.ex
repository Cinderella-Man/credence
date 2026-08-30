defmodule Credence.Pattern.PreferMultiClauseReduceFn do
  @moduledoc """
  Detects a two-argument anonymous function whose single clause is a nested
  `if/else` chain and rewrites it as a multi-clause pattern-matching `fn`,
  turning each `if` condition into a `when` guard.

  ## Bad

      Enum.reduce(list, {nil, 0}, fn element, {candidate, count} ->
        if count == 0 do
          {element, 1}
        else
          if element == candidate do
            {candidate, count + 1}
          else
            {candidate, count - 1}
          end
        end
      end)

  ## Good

      Enum.reduce(list, {nil, 0}, fn
        element, {candidate, count} when count == 0 -> {element, 1}
        element, {candidate, count} when element == candidate -> {candidate, count + 1}
        _element, {candidate, count} -> {candidate, count - 1}
      end)

  ## Safety

  The rewrite is deliberately conservative so it gives the **exact same answer**
  on every input:

    * Each condition becomes a `when` guard *verbatim* — conditions are never
      folded into the head pattern. Folding `count == 0` into the literal pattern
      `{candidate, 0}` would diverge: `count == 0` is true for both `0` and `0.0`,
      but the pattern `0` matches only the integer.
    * The rule fires only when **every** condition is a comparison
      (`==`, `!=`, `===`, `!==`, `<`, `>`, `<=`, `>=`) whose operands are plain
      variables or literals. Such conditions always return a boolean (so `if`'s
      truthiness matches a guard's strict `true`) and never raise (so the guard's
      error-swallowing can't change the result). Conditions with computed leaves
      (e.g. `count + 1 == 0`) or non-comparison calls are left alone.
    * The chain must end with an `else` branch, so the final clause is a genuine
      catch-all that maps to that branch. An innermost `if` without `else` is left
      alone — turning it into a catch-all would answer where the original returned
      `nil`.
  """
  use Credence.Pattern.Rule

  # DSL-unsafe in Nx.Defn only: the rewrite keeps/introduces an `if` in the reduce
  # function; inside `defn` `if` is a reinterpreted macro (scalar predicate, branch
  # shape/type unification), so the transformed fn is not equivalent.
  @impl true
  def unsafe_in_dsl, do: [:nx_defn]
  alias Credence.Issue

  @comparison_ops [:==, :!=, :===, :!==, :<, :>, :<=, :>=]

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case detect(node) do
          {:ok, meta} ->
            issue = %Issue{
              rule: :prefer_multi_clause_reduce_fn,
              message:
                "Anonymous function uses a nested if/else chain. " <>
                  "Prefer multi-clause pattern matching with guards.",
              meta: %{line: Keyword.get(meta, :line)}
            }

            {node, [issue | issues]}

          :error ->
            {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {:fn, _, _} = node ->
        case detect(node) do
          {:ok, _meta} -> build_multi_clause_fn(node)
          :error -> node
        end

      node ->
        node
    end)
  end

  # ── detection ──────────────────────────────────────────────────────

  defp detect({:fn, meta, [{:->, _, [args, body]}]})
       when is_list(args) and length(args) == 2 do
    with chain when is_list(chain) <- extract_if_chain(body),
         {nil, _} <- List.last(chain) do
      conditions = for {cond, _} <- chain, not is_nil(cond), do: cond

      if length(conditions) >= 2 and Enum.all?(conditions, &safe_guard_condition?/1) do
        {:ok, meta}
      else
        :error
      end
    else
      _ -> :error
    end
  end

  defp detect(_), do: :error

  # A condition is safe to move into a `when` guard only when it is a comparison
  # whose operands are plain variables or literals: such an expression always
  # returns a boolean and never raises, so neither guard truthiness nor guard
  # error-swallowing can change the answer.
  defp safe_guard_condition?({op, _, [lhs, rhs]}) when op in @comparison_ops,
    do: leaf?(lhs) and leaf?(rhs)

  defp safe_guard_condition?(_), do: false

  defp leaf?({:__block__, _, [literal]}), do: literal_value?(literal)
  defp leaf?({name, _, ctx}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)), do: true
  defp leaf?(other), do: literal_value?(other)

  defp literal_value?(v), do: is_number(v) or is_atom(v) or is_binary(v)

  # ── fix ────────────────────────────────────────────────────────────

  defp build_multi_clause_fn({:fn, meta, [{:->, _, [args, body]}]}) do
    [first_param, acc_pattern] = args
    chain = extract_if_chain(body)
    last_index = length(chain) - 1

    clauses =
      chain
      |> Enum.with_index()
      |> Enum.map(fn {{condition, branch}, index} ->
        build_clause(first_param, acc_pattern, condition, branch, index == last_index)
      end)

    {:fn, meta, clauses}
  end

  # Final clause: catch-all that maps to the `else` branch (condition is nil).
  defp build_clause(first_param, acc_pattern, _condition, branch, true) do
    param = maybe_underscore(first_param, [acc_pattern, branch])
    {:->, [], [[param, acc_pattern], branch]}
  end

  # Guarded clause: keep the condition verbatim as a `when` guard.
  defp build_clause(first_param, acc_pattern, condition, branch, false) do
    param = maybe_underscore(first_param, [acc_pattern, condition, branch])
    {:->, [], [[{:when, [], [param, acc_pattern, condition]}], branch]}
  end

  # ── AST helpers ────────────────────────────────────────────────────

  # Extract a flat list of {condition, branch} from a nested if/else, with a
  # trailing {nil, else_branch} when the innermost `if` has an `else`.
  defp extract_if_chain({:if, _, [condition, branches]}) when is_list(branches) do
    do_branch = extract_branch(branches, :do)
    else_branch = extract_branch(branches, :else)

    case else_branch do
      nil ->
        [{condition, do_branch}]

      inner_if ->
        case extract_if_chain(inner_if) do
          chain when is_list(chain) -> [{condition, do_branch} | chain]
          _ -> [{condition, do_branch}, {nil, inner_if}]
        end
    end
  end

  defp extract_if_chain(_), do: :error

  defp extract_branch(branches, key) when is_list(branches) do
    Enum.find_value(branches, fn
      {{:__block__, _, [^key]}, val} -> val
      _ -> nil
    end)
  end

  # Underscore the first param in a clause head only when it is a plain variable
  # that the clause's guard and branch never reference — that avoids an
  # unused-variable warning without ever unbinding a name the body needs.
  defp maybe_underscore({name, meta, ctx} = var, refs)
       when is_atom(name) and (is_nil(ctx) or is_atom(ctx)) do
    cond do
      String.starts_with?(to_string(name), "_") -> var
      Enum.any?(refs, &references?(&1, name)) -> var
      true -> {fresh_underscored_name(name, refs), meta, ctx}
    end
  end

  defp maybe_underscore(other, _refs), do: other

  defp fresh_underscored_name(name, refs, suffix \\ nil) do
    candidate = String.to_atom("_#{name}#{suffix}")

    if Enum.any?(refs, &references?(&1, candidate)) do
      fresh_underscored_name(name, refs, (suffix || 1) + 1)
    else
      candidate
    end
  end

  defp references?(ast, name) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {^name, _, ctx} = node, _acc when is_nil(ctx) or is_atom(ctx) -> {node, true}
        node, acc -> {node, acc}
      end)

    found?
  end
end
