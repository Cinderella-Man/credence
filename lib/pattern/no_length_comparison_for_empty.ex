defmodule Credence.Pattern.NoLengthComparisonForEmpty do
  @moduledoc """
  Detects `length(list)` comparisons with small integers (0–5) that can be
  replaced with O(1) pattern matching.

  `length/1` is O(n) on linked lists — it traverses every element to count
  them. LLMs use it freely because Python's `len()` is O(1). In Elixir,
  pattern matching can answer the same questions in O(1).

  ## Bad

      length(list) == 0
      length(list) > 0
      length(list) < 2
      length(list) >= 3

  ## Good

      list == []
      list != []
      !match?([_, _ | _], list)
      match?([_, _, _ | _], list)

  ## What is flagged

  Any comparison of `length(expr)` with a literal integer 0–5 using
  `==`, `!=`, `>`, `>=`, `<`, or `<=`. Reversed operands like
  `0 < length(list)` are also detected. Comparisons with larger
  integers are not flagged since the match pattern becomes unwieldy.

  ## Auto-fix

  Rewrites to `== []`, `!= []`, `match?/2`, or `!match?/2` depending
  on the comparison. Only fixes when the argument to `length/1` is a
  simple variable name.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @max_n 5

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case detect_pattern(node) do
          {:ok, meta} -> {node, [build_issue(meta) | acc]}
          :skip -> {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    guard_ids = collect_guard_member_ids(ast)
    collect_patches(ast, guard_ids)
  end

  # ── AST-based fix ───────────────────────────────────────────────
  #
  # `match?/2` desugars to `case`, which is not allowed in guards.
  # So we have to know *which* `length(x) op N` sites sit inside a
  # `:when` guard and leave those alone — otherwise the fix produces
  # code that no longer compiles. Walk the AST, collect the set of
  # node positions inside guards, and skip them when generating
  # source-range patches.

  defp collect_guard_member_ids(ast) do
    {_, ids} =
      Macro.prewalk(ast, MapSet.new(), fn
        # `:when` shape is {:when, _, [head_or_pattern, guard_expr | more_guards]}.
        # The first child is the call/pattern being guarded; everything after is
        # the guard expression (multiple entries indicate `when … when …` OR-chains).
        {:when, _, [_head | guard_parts]} = node, ids ->
          ids =
            Enum.reduce(guard_parts, ids, fn g, acc -> collect_subtree_ids(g, acc) end)

          {node, ids}

        node, ids ->
          {node, ids}
      end)

    ids
  end

  defp collect_subtree_ids(subtree, acc) do
    {_, acc} =
      Macro.prewalk(subtree, acc, fn
        {_, meta, _} = node, acc when is_list(meta) ->
          case node_id(meta) do
            nil -> {node, acc}
            id -> {node, MapSet.put(acc, id)}
          end

        node, acc ->
          {node, acc}
      end)

    acc
  end

  defp node_id(meta) do
    case {Keyword.get(meta, :line), Keyword.get(meta, :column)} do
      {nil, _} -> nil
      {_, nil} -> nil
      id -> id
    end
  end

  defp collect_patches(ast, guard_ids) do
    {_, patches} =
      Macro.prewalk(ast, [], fn node, acc ->
        case match_comparison(node) do
          {:ok, var, op, n, meta} ->
            cond do
              node_id(meta) in guard_ids ->
                {node, acc}

              replacement = build_replacement(var, op, n) ->
                {node, [%{range: Sourceror.get_range(node), change: replacement} | acc]}

              true ->
                {node, acc}
            end

          :skip ->
            {node, acc}
        end
      end)

    patches
  end

  # length(x) op N
  defp match_comparison({op, meta, [{:length, _, [arg]}, n_ast]})
       when op in [:==, :!=, :>, :>=, :<, :<=] do
    with {:ok, var} <- extract_var(arg),
         {:ok, n} <- extract_int(n_ast),
         true <- valid_comparison?(op, n) do
      {:ok, var, op, n, meta}
    else
      _ -> :skip
    end
  end

  # N op length(x)
  defp match_comparison({op, meta, [n_ast, {:length, _, [arg]}]})
       when op in [:==, :!=, :>, :>=, :<, :<=] do
    rev = reverse_op(op)

    with {:ok, var} <- extract_var(arg),
         {:ok, n} <- extract_int(n_ast),
         true <- valid_comparison?(rev, n) do
      {:ok, var, rev, n, meta}
    else
      _ -> :skip
    end
  end

  defp match_comparison(_), do: :skip

  defp extract_var({name, _meta, ctx}) when is_atom(name) and is_atom(ctx),
    do: {:ok, Atom.to_string(name)}

  defp extract_var(_), do: :error

  # Sourceror wraps integer literals in :__block__; Code.string_to_quoted doesn't.
  defp extract_int(n) when is_integer(n), do: {:ok, n}
  defp extract_int({:__block__, _, [n]}) when is_integer(n), do: {:ok, n}
  defp extract_int(_), do: :error

  # ── Detection ───────────────────────────────────────────────────

  # length(x) op N — only flag simple variables (matching what fix can handle)
  defp detect_pattern({op, meta, [{:length, _, [arg]}, n]})
       when is_integer(n) and op in [:==, :!=, :>, :>=, :<, :<=] do
    if simple_var?(arg) and valid_comparison?(op, n), do: {:ok, meta}, else: :skip
  end

  # N op length(x) — reversed operand, same simple-variable restriction
  defp detect_pattern({op, meta, [n, {:length, _, [arg]}]})
       when is_integer(n) and op in [:==, :!=, :>, :>=, :<, :<=] do
    rev = reverse_op(op)
    if simple_var?(arg) and valid_comparison?(rev, n), do: {:ok, meta}, else: :skip
  end

  defp detect_pattern(_), do: :skip

  # A simple variable in AST is {name, meta, context} where name is an atom
  # and context is nil or an atom. This excludes captures (&1), function calls
  # (hd(x)), dot-calls (Map.get(m, k)), etc. that the regex-based fix can't
  # rewrite.
  defp simple_var?({name, _meta, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp simple_var?(_), do: false

  # Check whether {op, n} is in our fixable range.
  # Each case generates a pattern with at most @max_n underscores.
  defp valid_comparison?(:==, n), do: n in 0..@max_n
  defp valid_comparison?(:!=, n), do: n in 0..@max_n
  # > N means "at least N+1" → need N+1 underscores → N+1 <= @max_n
  defp valid_comparison?(:>, n), do: n >= 0 and n + 1 <= @max_n
  # >= N means "at least N" → need N underscores → N in 1..@max_n
  defp valid_comparison?(:>=, n), do: n in 1..@max_n
  # < N means "fewer than N" → need N underscores → N in 1..@max_n
  defp valid_comparison?(:<, n), do: n in 1..@max_n
  # <= N means "fewer than N+1" → need N+1 underscores → N+1 <= @max_n
  defp valid_comparison?(:<=, n), do: n >= 0 and n + 1 <= @max_n

  defp reverse_op(:==), do: :==
  defp reverse_op(:!=), do: :!=
  defp reverse_op(:>), do: :<
  defp reverse_op(:<), do: :>
  defp reverse_op(:>=), do: :<=
  defp reverse_op(:<=), do: :>=

  # ── Replacement builders ────────────────────────────────────────

  # "exactly N"
  defp build_replacement(var, :==, 0), do: "#{var} == []"

  defp build_replacement(var, :==, n) when n in 1..@max_n,
    do: "match?(#{exact_pattern(n)}, #{var})"

  # "not exactly N"
  defp build_replacement(var, :!=, 0), do: "#{var} != []"

  defp build_replacement(var, :!=, n) when n in 1..@max_n,
    do: "!match?(#{exact_pattern(n)}, #{var})"

  # "at least N" (>= N)
  defp build_replacement(var, :>=, n) when n in 1..@max_n,
    do: at_least(var, n)

  # "at least N+1" (> N)
  defp build_replacement(var, :>, n) when n >= 0 and n + 1 <= @max_n,
    do: at_least(var, n + 1)

  # "fewer than N" (< N)
  defp build_replacement(var, :<, n) when n in 1..@max_n,
    do: fewer_than(var, n)

  # "fewer than N+1" (<= N)
  defp build_replacement(var, :<=, n) when n >= 0 and n + 1 <= @max_n,
    do: fewer_than(var, n + 1)

  defp build_replacement(_, _, _), do: nil

  defp at_least(var, 1), do: "#{var} != []"
  defp at_least(var, n), do: "match?(#{at_least_pattern(n)}, #{var})"

  defp fewer_than(var, 1), do: "#{var} == []"
  defp fewer_than(var, n), do: "!match?(#{at_least_pattern(n)}, #{var})"

  # ── Pattern generators ─────────────────────────────────────────

  # [_, _, _] — exactly N elements
  defp exact_pattern(n) do
    innards = List.duplicate("_", n) |> Enum.join(", ")
    "[#{innards}]"
  end

  # [_, _, _ | _] — at least N elements
  defp at_least_pattern(n) do
    innards = List.duplicate("_", n) |> Enum.join(", ")
    "[#{innards} | _]"
  end

  # ── Issue ───────────────────────────────────────────────────────

  defp build_issue(meta) do
    %Issue{
      rule: :no_length_comparison_for_empty,
      message: """
      `length/1` is O(n) on linked lists — it traverses every element \
      just to compare with a small number.

      Use pattern matching instead, which is O(1):

          list == []                        # empty
          list != []                        # non-empty
          match?([_, _ | _], list)          # at least 2
          match?([_, _, _], list)           # exactly 3
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
