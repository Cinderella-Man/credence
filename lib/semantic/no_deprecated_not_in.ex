defmodule Credence.Semantic.NoDeprecatedNotIn do
  @moduledoc """
  Rewrites the deprecated `not x in list` into `x not in list`.

  The compiler emits the diagnostic itself:

      "not expr1 in expr2" is deprecated, use "expr1 not in expr2" instead

  so nothing here has to decide *whether* the code is wrong — only how to repair
  it. That is the whole rule: the finding was already free, and Credence was
  reporting nothing and fixing nothing on a warning the compiler hands over on a
  plate.

  ## Why this cannot be an AST rewrite

  The two forms parse to the **same tree**. `not x in l` and `x not in l` are
  both `{:not, _, [{:in, _, [x, l]}]}`; the only difference is the `:not` node's
  **column** — 1 in the deprecated form, 3 in the modern one, because in the
  latter `not` sits after its left operand. So a rule that transformed the AST
  would produce output identical to its input and report `:no_op` forever.

  That column difference is also the detector. A `:not` whose column precedes
  its inner `:in`'s left operand is the deprecated spelling; one that follows it
  is already correct. The repair is therefore a byte-level splice over the
  expression's own range, rendered from the operands Sourceror already parsed.

  ## Equivalence

  Exact, and by definition rather than by argument: `expr1 not in expr2` is
  defined as `not (expr1 in expr2)`, which is what the deprecated form already
  means. The rewrite reorders source bytes and changes no evaluation — same
  operands, same order, same membership test, same negation.

  ## Bad

      defmodule NotInDeprecatedNDNI do
        def missing?(x, list), do: not x in list
      end

  ## Good

      defmodule NotInDeprecatedNDNI do
        def missing?(x, list), do: x not in list
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @message ~s("not expr1 in expr2" is deprecated)

  @impl true
  def match?(%{message: message}) when is_binary(message),
    do: String.contains?(message, @message)

  def match?(_diagnostic), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_deprecated_not_in,
      message: "`not x in list` is deprecated. Use `x not in list`, which means the same thing.",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    with target_line when is_integer(target_line) <- line(diagnostic),
         {:ok, ast} <- Sourceror.parse_string(source),
         [node | _] <- deprecated_nodes(ast, target_line) do
      Sourceror.patch_string(source, [patch(node)])
    else
      _ -> source
    end
  end

  # Every `not <lhs> in <rhs>` on `target_line` written in the deprecated order.
  #
  # The diagnostic names a line rather than a node, and a line can hold more
  # than one. Deepest-last ordering matters: a patch is applied to the outermost
  # match first, and `patch_string/2` re-renders that whole range from the
  # operands, so any nested occurrence inside it is rewritten by the same pass.
  # Applying more than one patch to overlapping ranges would corrupt the output.
  defp deprecated_nodes(ast, target_line) do
    {_ast, found} =
      Macro.prewalk(ast, [], fn
        {:not, meta, [{:in, _, [lhs, _rhs]}]} = node, acc ->
          if Keyword.get(meta, :line) == target_line and deprecated_order?(meta, lhs) do
            {node, [node | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  # `not` before its left operand is the deprecated spelling; `not` after it is
  # already `x not in l`. Comparing columns is the only thing that separates
  # them, since the trees are identical.
  #
  # A left operand spanning lines (`not\n  x in l`) has no meaningful column
  # comparison, so line is compared first and equal lines fall through to
  # column. An operand with no position at all — anything synthesised — is
  # declined rather than guessed at.
  defp deprecated_order?(not_meta, lhs) do
    with {not_line, not_col} when is_integer(not_line) <- position(not_meta),
         {lhs_line, lhs_col} when is_integer(lhs_line) <- position(lhs_meta(lhs)) do
      not_line < lhs_line or (not_line == lhs_line and not_col < lhs_col)
    else
      _ -> false
    end
  end

  defp lhs_meta({_form, meta, _args}) when is_list(meta), do: meta
  defp lhs_meta(_other), do: []

  defp position(meta) when is_list(meta) do
    {Keyword.get(meta, :line), Keyword.get(meta, :column)}
  end

  defp position(_meta), do: {nil, nil}

  # Render `<lhs> not in <rhs>` over the original expression's range. The
  # operands come back through `Sourceror.to_string/1`, so their own formatting
  # is preserved rather than reconstructed by hand.
  defp patch({:not, _meta, [{:in, _, [lhs, rhs]}]} = node) do
    %{
      range: Sourceror.get_range(node),
      change: "#{Sourceror.to_string(lhs)} not in #{Sourceror.to_string(rhs)}"
    }
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
  defp line(_diagnostic), do: nil
end
