defmodule Credence.Pattern.NoIdentityFloatCoercion do
  @moduledoc """
  Detects identity arithmetic used to coerce an integer to a float.

  LLMs carry Python idioms (`x * 1.0`, `x / 1.0`, `x + 0.0`) into Elixir,
  where they are unnecessary. If a float result is needed, Elixir's `/`
  operator always returns a float naturally.

  ## Detected patterns

      expr * 1.0      1.0 * expr
      expr / 1.0
      expr + 0.0      0.0 + expr
      expr - 0.0

  Note: `0.0 - expr` is NOT flagged — it negates, not coerces.

  ## Bare-variable skip

  When the non-identity operand is a bare variable (`n * 1.0`), the rule
  skips it — the variable's type is unknown, and `* 1.0` may be intentional
  int → float coercion. Compound expressions (`(a + b) * 1.0`), function
  calls (`Enum.at(list, 0) * 1.0`), and literals are still flagged because
  the `* 1.0` is overwhelmingly a Python-ism in those contexts.

  The companion rule `PreferErlangFloat` handles the bare-variable cases
  by rewriting `n * 1.0` to `:erlang.float(n)`.

  ## Bad

      Enum.at(sorted_list, mid) * 1.0

      Enum.at(combined, mid_index) / 1.0

  ## Good

      Enum.at(sorted_list, mid)

      Enum.at(combined, mid_index)

  ## Auto-fix

  Removes the identity operand and operator from the expression. When the
  entire line is a no-op self-assignment (`var = var * 1.0`), the line is
  deleted.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {op, meta, [left, right]} = node, acc when op in [:*, :/, :+, :-] ->
          {node, maybe_flag(op, meta, left, right, acc)}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  defp maybe_flag(op, meta, left, right, acc) do
    right_val = unwrap_float(right)
    left_val = unwrap_float(left)

    cond do
      is_float(right_val) and identity_right?(op, right_val) and not bare_var?(left) ->
        [build_issue(op, right_val, meta) | acc]

      op in [:*, :+] and is_float(left_val) and identity_left?(op, left_val) and
          not bare_var?(right) ->
        [build_issue(op, left_val, meta) | acc]

      true ->
        acc
    end
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)
    collect_patches(ast, source)
  end

  # Walks the Sourceror AST, finds each identity-strip site, and emits a
  # patch covering the whole `expr OP identity` range, replaced by the
  # *original source bytes* of the kept subexpression. Slicing source
  # bytes (rather than re-rendering the AST) preserves `(a - b)` parens
  # verbatim — Sourceror's renderer drops them on standalone subtrees.
  defp collect_patches(ast, source) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn
        {op, _meta, [left, right]} = node, acc when op in [:*, :/, :+, :-] ->
          cond do
            identity_right?(op, unwrap_float(right)) and not bare_var?(left) ->
              {node, add_strip_patch(acc, node, left, source)}

            op in [:*, :+] and identity_left?(op, unwrap_float(left)) and
                not bare_var?(right) ->
              {node, add_strip_patch(acc, node, right, source)}

            true ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(patches)
  end

  defp add_strip_patch(acc, outer_node, kept_node, source) do
    with %Sourceror.Range{} = outer_range <- Sourceror.get_range(outer_node),
         %Sourceror.Range{} = kept_range <- Sourceror.get_range(kept_node) do
      [
        %{range: outer_range, change: slice_range(source, kept_range)}
        | acc
      ]
    else
      _ -> acc
    end
  end

  # Slice the original source bytes corresponding to a Sourceror.Range.
  # Faithful to the source — includes any leading/trailing parens captured
  # in the range.
  defp slice_range(source, %Sourceror.Range{start: s, end: e}) do
    lines = String.split(source, "\n")

    start_offset =
      lines
      |> Enum.take(s[:line] - 1)
      |> Enum.map(&(byte_size(&1) + 1))
      |> Enum.sum()
      |> Kernel.+(s[:column] - 1)

    end_offset =
      lines
      |> Enum.take(e[:line] - 1)
      |> Enum.map(&(byte_size(&1) + 1))
      |> Enum.sum()
      |> Kernel.+(e[:column] - 1)

    binary_part(source, start_offset, end_offset - start_offset)
  end

  # Sourceror wraps variables in {:__block__, _, [var_node]}.
  defp bare_var?({:__block__, _, [inner]}), do: bare_var?(inner)
  defp bare_var?({name, _meta, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp bare_var?(_), do: false

  # Right-hand identity:  expr * 1.0,  expr / 1.0,  expr + 0.0,  expr - 0.0
  defp identity_right?(:*, 1.0), do: true
  defp identity_right?(:/, 1.0), do: true
  defp identity_right?(:+, +0.0), do: true
  defp identity_right?(:-, +0.0), do: true
  defp identity_right?(_, _), do: false

  # Left-hand identity (commutative only):  1.0 * expr,  0.0 + expr
  # NOT: 0.0 - expr (negation), 1.0 / expr (reciprocal)
  defp identity_left?(:*, 1.0), do: true
  defp identity_left?(:+, +0.0), do: true
  defp identity_left?(_, _), do: false

  # Sourceror wraps float literals in {:__block__, meta, [value]}.
  defp unwrap_float({:__block__, _, [val]}) when is_float(val), do: val
  defp unwrap_float(_), do: nil

  defp build_issue(op, val, meta) do
    identity = if val == 1.0, do: "1.0", else: "0.0"
    op_str = Atom.to_string(op)

    %Issue{
      rule: :no_identity_float_coercion,
      message:
        "`#{op_str} #{identity}` to convert to float is a Python idiom " <>
          "that is unnecessary in Elixir. Remove it.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
