defmodule Credence.Pattern.NoUnusedUnderscoreAssignment do
  @moduledoc """
  Removes a dead `_var = <pure>` binding left behind by the unused-variable fix.

  When the semantic `UnusedVariable` rule prefixes an unused variable with `_`,
  it leaves a dead assignment such as `_length = list` whose value is never
  read. A human deterministically deletes that line.

  ## Example

      # Bad
      def process(list) do
        _length = list
        n = length(list)
        if n < 3, do: 0, else: n
      end

      # Good
      def process(list) do
        n = length(list)
        if n < 3, do: 0, else: n
      end

  ## Safe core (narrowed)

  An assignment is removed only when **all** hold, so the deletion can never
  change behaviour:

    * the left side is a single underscore-prefixed variable (`_name`), not a
      destructuring pattern;
    * the right side is a **trivially pure** expression — a literal (number,
      atom, string, boolean, nil) or a bare variable — so removing it skips no
      side effect and can raise nothing;
    * the variable name occurs exactly **once** in the whole input (this binding
      and nowhere else), so nothing reads it;
    * the assignment is **not** the last expression of its block (the last
      expression is the block's value).

  Anything outside that core (a call/operator RHS, a referenced variable, a
  destructuring left side, a last-position binding) is left untouched.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    freq = var_frequencies(ast)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:__block__, _meta, statements} = node, acc when is_list(statements) ->
          {node, deletable_statements(statements, freq) |> Enum.map(&build_issue/1) |> Kernel.++(acc)}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    freq = var_frequencies(ast)
    Credence.RuleHelpers.patches_from_postwalk(ast, &maybe_rewrite_block(&1, freq))
  end

  defp maybe_rewrite_block({:__block__, meta, statements}, freq)
       when is_list(statements) and length(statements) >= 2 do
    deletable = deletable_statements(statements, freq)

    if deletable == [] do
      {:__block__, meta, statements}
    else
      {:__block__, meta, statements -- deletable}
    end
  end

  defp maybe_rewrite_block(node, _freq), do: node

  # Every statement except the last that is a removable dead underscore binding.
  defp deletable_statements(statements, freq) when length(statements) >= 2 do
    {non_last, _last} = Enum.split(statements, length(statements) - 1)
    Enum.filter(non_last, &deletable?(&1, freq))
  end

  defp deletable_statements(_statements, _freq), do: []

  defp deletable?({:=, _meta, [lhs, rhs]}, freq) do
    case underscore_var(lhs) do
      {:ok, name} -> Map.get(freq, name) == 1 and trivially_pure?(rhs)
      :error -> false
    end
  end

  defp deletable?(_node, _freq), do: false

  # A single underscore-prefixed variable on the left side, never a pattern.
  defp underscore_var({name, _meta, ctx}) when is_atom(name) and is_atom(ctx) do
    str = Atom.to_string(name)
    if String.starts_with?(str, "_"), do: {:ok, name}, else: :error
  end

  defp underscore_var(_), do: :error

  # Literals and bare variables only — provably free of side effects and of
  # anything that could raise.
  defp trivially_pure?({:__block__, _meta, [inner]}), do: trivially_pure?(inner)

  defp trivially_pure?(lit)
       when is_integer(lit) or is_float(lit) or is_atom(lit) or is_binary(lit),
       do: true

  defp trivially_pure?({name, _meta, ctx}) when is_atom(name) and is_atom(ctx), do: true

  defp trivially_pure?(_), do: false

  # Count every variable reference (atom name, atom context) in the AST.
  defp var_frequencies(ast) do
    {_ast, freq} =
      Macro.prewalk(ast, %{}, fn
        {name, _meta, ctx} = node, acc when is_atom(name) and is_atom(ctx) ->
          {node, Map.update(acc, name, 1, &(&1 + 1))}

        node, acc ->
          {node, acc}
      end)

    freq
  end

  defp build_issue({:=, meta, [_lhs, _rhs]}) do
    %Issue{
      rule: :no_unused_underscore_assignment,
      message:
        "Dead assignment: the underscore-prefixed variable is never read and " <>
          "its value is a pure expression. Remove the line.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
