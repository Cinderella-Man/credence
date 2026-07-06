defmodule Credence.Pattern.PreferStdlibGcd do
  @moduledoc """
  Detects hand-rolled GCD implementations that duplicate `Integer.gcd/2`.

  `Integer.gcd/2` has been available since Elixir 1.5 and is the idiomatic way
  to compute the greatest common divisor. A private `gcd/2` function implementing
  the Euclidean algorithm is unnecessary boilerplate.

  ## Bad

      defp gcd(a, 0), do: a
      defp gcd(a, b), do: gcd(b, rem(a, b))

  ## Good

      Integer.gcd(a, b)

  ## Behaviour note — non-negative domain

  `Integer.gcd/2` always returns a NON-NEGATIVE result, whereas the hand-rolled
  base case `gcd(a, 0) => a` returns `a` unchanged. The two therefore diverge on
  NEGATIVE inputs (e.g. `gcd(-4, 0)` yields `-4`, but `Integer.gcd(-4, 0)` yields
  `4`). Equivalence holds only on GCD's natural non-negative domain — the inputs
  for which a greatest *common divisor* is meaningfully defined. Callers that only
  feed non-negative integers (the overwhelmingly common case, e.g. an LCM helper
  guarded on positive arguments) are unaffected; the rewrite is behaviour-
  preserving there.
  """

  use Credence.Pattern.Rule
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case detect_euclidean_gcd(node) do
          {:ok, line} ->
            issue = %Issue{
              rule: :prefer_stdlib_gcd,
              message:
                "Hand-rolled GCD duplicates `Integer.gcd/2`. " <>
                  "Use `Integer.gcd/2` from stdlib instead.",
              meta: %{line: line}
            }

            {node, [issue | acc]}

          :skip ->
            {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_ast_transform(ast, Sourceror.to_string(ast), fn tree ->
      Macro.prewalk(tree, fn
        {:__block__, meta, stmts} when is_list(stmts) ->
          case find_euclidean_gcd_pair_index(stmts) do
            {:ok, i} ->
              {before, rest} = Enum.split(stmts, i)
              remaining = before ++ Enum.drop(rest, 2)
              # Replace bare gcd calls in the remaining statements
              replaced = Enum.map(remaining, &replace_gcd_calls/1)
              {:__block__, meta, replaced}

            :not_found ->
              {:__block__, meta, stmts}
          end

        node ->
          node
      end)
    end)
  end

  # Detect the two-clause Euclidean algorithm pattern in a __block__.
  # Scans consecutive statement pairs for:
  #   defp gcd(a, 0), do: a
  #   defp gcd(a, b), do: gcd(b, rem(a, b))
  defp detect_euclidean_gcd({:__block__, _meta, stmts}) when is_list(stmts) do
    case find_euclidean_gcd_pair_line(stmts) do
      {:ok, line} -> {:ok, line}
      :not_found -> :skip
    end
  end

  defp detect_euclidean_gcd(_), do: :skip

  # Find consecutive defp gcd clauses and return the line of the first one.
  defp find_euclidean_gcd_pair_line(stmts) do
    stmts
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(:not_found, fn
      [clause1, clause2] ->
        with :ok <- gcd_base_clause(clause1),
             :ok <- gcd_recursive_clause(clause2) do
          {:ok, elem(clause1, 1) |> Keyword.get(:line)}
        else
          _ -> nil
        end

      _ ->
        nil
    end)
  end

  # Find the index of the first defp in a Euclidean gcd pair.
  defp find_euclidean_gcd_pair_index(stmts) do
    stmts
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.find_value(:not_found, fn
      {[clause1, clause2], i} ->
        with :ok <- gcd_base_clause(clause1),
             :ok <- gcd_recursive_clause(clause2) do
          {:ok, i}
        else
          _ -> nil
        end

      _ ->
        nil
    end)
  end

  # Matches: defp gcd(a, 0), do: a
  defp gcd_base_clause({:defp, _meta, [head, body]}) do
    case head do
      {:gcd, _, [{a, _, ctx_a}, {:__block__, _, [0]}]}
      when is_atom(a) and is_atom(ctx_a) ->
        case body do
          [{{:__block__, _, [:do]}, {ret, _, ctx_ret}}]
          when is_atom(ret) and is_atom(ctx_ret) ->
            if ret == a, do: :ok, else: :error

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  defp gcd_base_clause(_), do: :error

  # Matches: defp gcd(a, b), do: gcd(b, rem(a, b))
  defp gcd_recursive_clause({:defp, _meta, [head, body]}) do
    case head do
      {:gcd, _, [{a, _, ctx_a}, {b, _, ctx_b}]}
      when is_atom(a) and is_atom(ctx_a) and is_atom(b) and is_atom(ctx_b) ->
        case body do
          [{{:__block__, _, [:do]},
            {:gcd, _,
             [
               {b2, _, ctx_b2},
               {:rem, _, [{a2, _, ctx_a2}, {b3, _, ctx_b3}]}
             ]}}]
          when is_atom(b2) and is_atom(ctx_b2) and
                 is_atom(a2) and is_atom(ctx_a2) and
                 is_atom(b3) and is_atom(ctx_b3) ->
            # Within the recursive clause: gcd(b, rem(a, b))
            # a2 must match the first param (a), b2 and b3 must match second param (b)
            if a2 == a and b2 == b and b3 == b, do: :ok, else: :error

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  defp gcd_recursive_clause(_), do: :error

  # Replace bare gcd(x, y) calls with Integer.gcd(x, y) in an AST node.
  defp replace_gcd_calls(node) do
    Macro.postwalk(node, fn
      {:gcd, _meta, [arg1, arg2]} = node ->
        if bare_var?(arg1) and bare_var?(arg2) do
          {{:., [], [{:__aliases__, [], [:Integer]}, :gcd]}, [], [arg1, arg2]}
        else
          node
        end

      node ->
        node
    end)
  end

  defp bare_var?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp bare_var?(_), do: false
end
