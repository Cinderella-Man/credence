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

  ## Bad

      Enum.at(sorted_list, mid) * 1.0

      Enum.at(combined, mid_index) / 1.0

      count = count + 0.0

  ## Good

      Enum.at(sorted_list, mid)

      Enum.at(combined, mid_index)

      # (self-assignment line removed entirely)

  ## Auto-fix

  Removes the identity operand and operator from the expression. When the
  entire line is a no-op self-assignment (`var = var * 1.0`), the line is
  deleted.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  # ── Check ─────────────────────────────────────────────────────────
  # Uses AST from Code.string_to_quoted (bare float literals).

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # expr OP identity  (right-hand identity)
        {op, meta, [_expr, val]} = node, acc
        when is_float(val) and op in [:*, :/, :+, :-] ->
          if identity_right?(op, val) do
            {node, [build_issue(op, val, meta) | acc]}
          else
            {node, acc}
          end

        # identity OP expr  (left-hand identity, commutative ops only)
        {op, meta, [val, _expr]} = node, acc
        when is_float(val) and op in [:*, :+] ->
          if identity_left?(op, val) do
            {node, [build_issue(op, val, meta) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  # ── Fix ───────────────────────────────────────────────────────────
  # Uses Sourceror for parsing (wraps literals in __block__).

  @impl true
  def fix(source, _opts) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        target_lines = find_target_lines(ast)

        if target_lines == [] do
          source
        else
          line_set = MapSet.new(target_lines)

          source
          |> String.split("\n")
          |> Enum.with_index(1)
          |> Enum.flat_map(fn {line, idx} ->
            if idx in line_set do
              case fix_line(line) do
                :delete -> []
                fixed -> [fixed]
              end
            else
              [line]
            end
          end)
          |> Enum.join("\n")
        end

      {:error, _} ->
        source
    end
  end

  # ── Target-line collection (Sourceror AST) ────────────────────────

  defp find_target_lines(ast) do
    {_ast, lines} =
      Macro.prewalk(ast, [], fn
        # Single clause checks both sides — two clauses would shadow each
        # other because the first always matches any binary op node.
        {op, meta, [left, right]} = node, acc when op in [:*, :/, :+, :-] ->
          hit_right = identity_right?(op, unwrap_float(right))
          hit_left = op in [:*, :+] and identity_left?(op, unwrap_float(left))

          if hit_right or hit_left do
            {node, [Keyword.get(meta, :line) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(lines)
  end

  # ── Line-level rewriting (regex) ──────────────────────────────────

  defp fix_line(line) do
    if self_assign_identity?(line) do
      :delete
    else
      remove_identity_ops(line)
    end
  end

  # Self-assignment: var = var OP IDENTITY  →  delete entire line
  defp self_assign_identity?(line) do
    # var = var * 1.0
    # var = 1.0 * var
    # var = var / 1.0
    # var = var + 0.0
    # var = 0.0 + var
    # var = var - 0.0
    Regex.match?(~r/^\s*(\w+)\s*=\s*\1\s*\*\s*1\.0(?![0-9eE_])\s*$/, line) or
      Regex.match?(~r/^\s*(\w+)\s*=\s*1\.0(?![0-9eE_])\s*\*\s*\1\s*$/, line) or
      Regex.match?(~r/^\s*(\w+)\s*=\s*\1\s*\/\s*1\.0(?![0-9eE_])\s*$/, line) or
      Regex.match?(~r/^\s*(\w+)\s*=\s*\1\s*\+\s*0\.0(?![0-9eE_])\s*$/, line) or
      Regex.match?(~r/^\s*(\w+)\s*=\s*0\.0(?![0-9eE_])\s*\+\s*\1\s*$/, line) or
      Regex.match?(~r/^\s*(\w+)\s*=\s*\1\s*\-\s*0\.0(?![0-9eE_])\s*$/, line)
  end

  # Strip identity operand+operator from the expression
  defp remove_identity_ops(line) do
    line
    # Trailing: expr OP IDENTITY
    |> then(&Regex.replace(~r/\s*\*\s*1\.0(?![0-9eE_])/, &1, ""))
    |> then(&Regex.replace(~r/\s*\/\s*1\.0(?![0-9eE_])/, &1, ""))
    |> then(&Regex.replace(~r/\s*\+\s*0\.0(?![0-9eE_])/, &1, ""))
    |> then(&Regex.replace(~r/\s*\-\s*0\.0(?![0-9eE_])/, &1, ""))
    # Leading: IDENTITY OP expr
    |> then(&Regex.replace(~r/1\.0(?![0-9eE_])\s*\*\s*/, &1, ""))
    |> then(&Regex.replace(~r/0\.0(?![0-9eE_])\s*\+\s*/, &1, ""))
  end

  # ── Identity helpers ──────────────────────────────────────────────

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
  # This normalises both representations.
  defp unwrap_float({:__block__, _, [val]}) when is_float(val), do: val
  defp unwrap_float(val) when is_float(val), do: val
  defp unwrap_float(_), do: nil

  # ── Issue construction ────────────────────────────────────────────

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
