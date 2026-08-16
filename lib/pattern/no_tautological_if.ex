defmodule Credence.Pattern.NoTautologicalIf do
  @moduledoc """
  Detects `if/else` expressions where both branches return the same value.

  When both the `do` and `else` branches produce identical code, the
  condition is irrelevant — the entire `if/else` can be replaced with
  the body of either branch.

  ## Detected patterns

      if condition do
        result
      else
        result
      end

      if swapped do
        result
      else
        result
      end

      if condition, do: value, else: value

  ## Bad

      def check(x) do
        if x > 0, do: value, else: value
      end

  ## Good

      result

      value

  ## Auto-fix

  Replaces the entire `if/else` with the `do` branch body.

  ## Safety: why this is narrowed

  Deleting the `if` also deletes the **condition**, so the condition must be
  provably free of side effects and exceptions — otherwise dropping it changes
  behaviour (a side-effecting or raising condition would no longer run). We only
  fire when the condition is a *pure, total* expression: a variable, a literal,
  or a comparison of such. Any function call (`foo()`, `f(x)`) or assignment
  (`x = ...`) in the condition is excluded.

  Lifting the branch body out of the `if` scope also makes any variable the
  body **binds** leak to the surrounding scope, which can shadow an outer
  variable used later. We therefore only fire when the body contains no match
  (`=`) — bindings inside `fn`/`case`/`for`/etc. are scoped and harmless, but a
  bare `=` could leak, so we exclude the whole body if any `=` appears.
  """

  use Credence.Pattern.Rule

  # DSL-unsafe in Nx.Defn only: deleting the `if` together with its condition
  # assumes the condition is pure and total. In Nx.Defn the condition's `>` is an
  # element-wise tensor op and `if` requires a scalar predicate, so the discarded
  # condition can raise — removing it changes behaviour.
  @impl true
  def unsafe_in_dsl, do: [:nx_defn]
  alias Credence.Issue

  # Term-comparison operators are total (never raise) and side-effect free.
  @comparison_ops [:>, :<, :>=, :<=, :==, :!=, :===, :!==]

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:if, meta, [condition, clauses]} = node, acc when is_list(clauses) ->
          if flaggable?(condition, clauses) do
            {node, [build_issue(meta) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {:if, _meta, [condition, clauses]} = node when is_list(clauses) ->
        if flaggable?(condition, clauses) do
          extract_clause(clauses, :do)
        else
          node
        end

      node ->
        node
    end)
  end

  # check and fix agree on exactly this predicate.
  defp flaggable?(condition, clauses) do
    tautological_if?(clauses) and pure_condition?(condition) and
      not binds_variable?(extract_clause(clauses, :do))
  end

  defp tautological_if?(clauses) do
    do_body = extract_clause(clauses, :do)
    else_body = extract_clause(clauses, :else)

    do_body != nil and else_body != nil and ast_equal?(do_body, else_body)
  end

  # A condition we can safely delete: no side effects, never raises.
  # Literals (Sourceror wraps them in a :__block__ node) ...
  defp pure_condition?({:__block__, _, [lit]})
       when is_number(lit) or is_atom(lit) or is_binary(lit),
       do: true

  # ... comparisons of pure operands (total term ordering, never raises) ...
  defp pure_condition?({op, _, [a, b]}) when op in @comparison_ops,
    do: pure_condition?(a) and pure_condition?(b)

  # ... and variables / special forms (3rd element is an atom context, not a
  # call's argument list). A bare identifier is always a variable in valid
  # code — the compiler rejects bare 0-arity calls.
  defp pure_condition?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp pure_condition?(_), do: false

  # True if the body contains any match (`=`) that could leak a binding into the
  # enclosing scope once the `if` wrapper is removed.
  defp binds_variable?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {:=, _, _} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found?
  end

  # Extract the body for a given clause key (:do or :else).
  defp extract_clause(clauses, key) do
    Enum.find_value(clauses, fn
      {{:__block__, _, [^key]}, body} -> body
      _ -> nil
    end)
  end

  # Deep structural equality on AST, ignoring metadata (line numbers, etc.)
  defp ast_equal?(a, b) do
    strip_meta(a) == strip_meta(b)
  end

  defp strip_meta({form, _meta, args}) do
    {strip_meta(form), nil, strip_meta(args)}
  end

  defp strip_meta(list) when is_list(list), do: Enum.map(list, &strip_meta/1)
  defp strip_meta({a, b}), do: {strip_meta(a), strip_meta(b)}
  defp strip_meta(other), do: other

  defp build_issue(meta) do
    %Issue{
      rule: :no_tautological_if,
      message:
        "Both branches of this `if/else` return the same value. " <>
          "Replace the entire expression with the branch body.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
