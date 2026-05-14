defmodule Credence.Pattern.PreferErlangFloat do
  @moduledoc """
  Replaces bare-variable float coercion tricks with explicit `:erlang.float/1`.

  LLMs (and developers) use `n * 1.0`, `n / 1.0`, `n + 0.0`, or `n - 0.0`
  to coerce an integer to a float. These are arithmetic tricks borrowed from
  Python — `:erlang.float/1` expresses the same intent explicitly and works
  whether the input is an integer (converts) or already a float (returns it).

  This rule only handles **bare-variable** operands. Compound expressions
  and function calls (`(a + b) * 1.0`, `Enum.sum(list) * 1.0`) are handled
  by `NoIdentityFloatCoercion`, which removes the identity outright — those
  are overwhelmingly Python-isms, not intentional coercion.

  ## Priority

  This rule runs at priority 501 (above the default 500) so it processes
  bare-variable sites **before** `NoIdentityFloatCoercion`. This matters
  when both kinds share a line — e.g. `{n * 1.0, Enum.sum(xs) * 1.0}`.
  Without the higher priority, `NoIdentityFloatCoercion`'s line-level regex
  would strip all `* 1.0` on the line, including the bare-variable site
  that should become `:erlang.float(n)`.

  ## Detected patterns

      var * 1.0      1.0 * var
      var / 1.0
      var + 0.0      0.0 + var
      var - 0.0

  Note: `0.0 - var` is NOT flagged — it negates, not coerces.

  ## Bad

      defp to_float(n) when is_integer(n), do: n * 1.0

      count = count + 0.0

  ## Good

      defp to_float(n) when is_integer(n), do: :erlang.float(n)

      count = :erlang.float(count)

  ## Auto-fix

  Replaces the identity arithmetic with `:erlang.float(var)`.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  # Run before NoIdentityFloatCoercion (priority 500) so bare-variable
  # sites are rewritten to :erlang.float(var) before the sibling rule's
  # line-level regex strips all `* 1.0` indiscriminately.
  @impl true
  def priority, do: 499

  # ── Check ─────────────────────────────────────────────────────────
  # Uses AST from Code.string_to_quoted (bare float literals).

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # bare_var OP identity  (right-hand identity)
        {op, meta, [expr, val]} = node, acc
        when is_float(val) and op in [:*, :/, :+, :-] ->
          if identity_right?(op, val) and bare_var?(expr) do
            {node, [build_issue(meta) | acc]}
          else
            {node, acc}
          end

        # identity OP bare_var  (left-hand identity, commutative ops only)
        {op, meta, [val, expr]} = node, acc
        when is_float(val) and op in [:*, :+] ->
          if identity_left?(op, val) and bare_var?(expr) do
            {node, [build_issue(meta) | acc]}
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
          |> Enum.map(fn {line, idx} ->
            if idx in line_set, do: replace_with_erlang_float(line), else: line
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
        {op, meta, [left, right]} = node, acc when op in [:*, :/, :+, :-] ->
          hit_right = identity_right?(op, unwrap_float(right)) and bare_var?(left)

          hit_left =
            op in [:*, :+] and identity_left?(op, unwrap_float(left)) and bare_var?(right)

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

  @no_ext ~S"(?![0-9eE_])"

  defp replace_with_erlang_float(line) do
    line
    # Trailing: var OP IDENTITY → :erlang.float(var)
    |> then(&Regex.replace(~r/(\w+)\s*\*\s*1\.0#{@no_ext}/, &1, ":erlang.float(\\1)"))
    |> then(&Regex.replace(~r/(\w+)\s*\/\s*1\.0#{@no_ext}/, &1, ":erlang.float(\\1)"))
    |> then(&Regex.replace(~r/(\w+)\s*\+\s*0\.0#{@no_ext}/, &1, ":erlang.float(\\1)"))
    |> then(&Regex.replace(~r/(\w+)\s*\-\s*0\.0#{@no_ext}/, &1, ":erlang.float(\\1)"))
    # Leading: IDENTITY OP var → :erlang.float(var)
    |> then(&Regex.replace(~r/1\.0#{@no_ext}\s*\*\s*(\w+)/, &1, ":erlang.float(\\1)"))
    |> then(&Regex.replace(~r/0\.0#{@no_ext}\s*\+\s*(\w+)/, &1, ":erlang.float(\\1)"))
  end

  # ── Bare-variable detection ──────────────────────────────────────

  # Sourceror wraps variables in {:__block__, _, [var_node]}.
  defp bare_var?({:__block__, _, [inner]}), do: bare_var?(inner)
  defp bare_var?({name, _meta, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp bare_var?(_), do: false

  # ── Identity helpers ──────────────────────────────────────────────

  defp identity_right?(:*, 1.0), do: true
  defp identity_right?(:/, 1.0), do: true
  defp identity_right?(:+, +0.0), do: true
  defp identity_right?(:-, +0.0), do: true
  defp identity_right?(_, _), do: false

  defp identity_left?(:*, 1.0), do: true
  defp identity_left?(:+, +0.0), do: true
  defp identity_left?(_, _), do: false

  # Sourceror wraps float literals in {:__block__, meta, [value]}.
  defp unwrap_float({:__block__, _, [val]}) when is_float(val), do: val
  defp unwrap_float(val) when is_float(val), do: val
  defp unwrap_float(_), do: nil

  # ── Issue construction ────────────────────────────────────────────

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_erlang_float,
      message:
        "Use `:erlang.float(var)` for int → float coercion instead of " <>
          "arithmetic identity tricks (`* 1.0`, `/ 1.0`, `+ 0.0`, `- 0.0`).",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
