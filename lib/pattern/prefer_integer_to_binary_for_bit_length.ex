defmodule Credence.Pattern.PreferIntegerToBinaryForBitLength do
  @moduledoc """
  Detects `floor(:math.log(n) / :math.log(2)) + 1` used for integer bit-length
  computation and rewrites to `:erlang.integer_to_binary/2` for correctness and
  efficiency. Also adds a negative-integer clause when inside a `def` with a
  `when n > 0` guard.

  ## Bad

      def num_of_bits(n) when n > 0 do
        floor(:math.log(n) / :math.log(2)) + 1
      end

  ## Good

      def num_of_bits(n) when n > 0 do
        n
        |> :erlang.integer_to_binary(2)
        |> String.length()
      end

      def num_of_bits(n) when n < 0 do
        num_of_bits(-n)
      end
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:+, meta, [floor_call, one]} = node, acc ->
          case match_log2_plus_one(floor_call, one) do
            {:ok, _var} -> {node, [build_issue(meta) | acc]}
            :no -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.get(opts, :source, Sourceror.to_string(ast))

    RuleHelpers.patches_from_ast_transform(ast, source, fn ast ->
      Macro.postwalk(ast, fn
        # Replace the log expression (children processed first, so this runs
        # before the defmodule handler below)
        {:+, _meta, [floor_call, one]} = node ->
          case match_log2_plus_one(floor_call, one) do
            {:ok, var} -> build_integer_to_binary_pipe(var)
            :no -> node
          end

        # At the module level, insert negative clause for defs that were rewritten
        {:defmodule, mod_meta, [aliases, [{{:__block__, do_meta, [:do]}, body}]]} ->
          new_body = insert_negative_if_rewritten(body)
          {:defmodule, mod_meta, [aliases, [{{:__block__, do_meta, [:do]}, new_body}]]}

        {:defmodule, mod_meta, [aliases, [do_kw]]} when is_list(do_kw) ->
          case RuleHelpers.extract_do_body(do_kw) do
            {:ok, body} ->
              new_body = insert_negative_if_rewritten(body)
              {:defmodule, mod_meta, [aliases, RuleHelpers.replace_do_body(do_kw, new_body)]}

            :error ->
              {:defmodule, mod_meta, [aliases, [do_kw]]}
          end

        node ->
          node
      end)
    end)
  end

  defp insert_negative_if_rewritten({:__block__, meta, stmts}) do
    {new_stmts, _added?} =
      Enum.reduce(stmts, {[], false}, fn stmt, {acc, added?} ->
        case positive_guard_def_with_integer_to_binary(stmt) do
          {:ok, fun_name, var_name} when not added? ->
            neg_clause = build_negative_clause(fun_name, var_name)
            {acc ++ [stmt, neg_clause], true}

          _ ->
            {acc ++ [stmt], added?}
        end
      end)

    {:__block__, meta, new_stmts}
  end

  defp insert_negative_if_rewritten(single) do
    case positive_guard_def_with_integer_to_binary(single) do
      {:ok, fun_name, var_name} ->
        neg_clause = build_negative_clause(fun_name, var_name)
        {:__block__, [], [single, neg_clause]}

      :no ->
        single
    end
  end

  # Match a def with `when var > 0` guard whose body contains
  # `:erlang.integer_to_binary` (the result of the log-expression replacement).
  defp positive_guard_def_with_integer_to_binary(
         {:def, _meta, [{:when, _, [fun_head, guard]}, body_kw]}
       ) do
    {fun_name, _, _} = fun_head

    with {:>, _, [{var_name, _, ctx}, {:__block__, _, [0]}]} <- guard,
         true <- is_atom(var_name) and is_atom(ctx),
         true <- body_has_integer_to_binary?(body_kw) do
      {:ok, fun_name, var_name}
    else
      _ -> :no
    end
  end

  defp positive_guard_def_with_integer_to_binary(_), do: :no

  defp body_has_integer_to_binary?(body_kw) when is_list(body_kw) do
    case RuleHelpers.extract_do_body(body_kw) do
      {:ok, body} -> contains_integer_to_binary?(body)
      :error -> false
    end
  end

  defp contains_integer_to_binary?(ast) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {{:., _, [:erlang, :integer_to_binary]}, _, _} = node, _ -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  defp build_negative_clause(fun_name, var_name) do
    var = {var_name, [], nil}
    fun_head = {fun_name, [], [var]}
    guard = {:<, [], [var, {:__block__, [], [0]}]}
    negated = {:-, [], [var]}
    body = {fun_name, [], [negated]}

    {:def, [],
     [
       {:when, [], [fun_head, guard]},
       [{{:__block__, [], [:do]}, body}]
     ]}
  end

  # ── Pattern matching ──────────────────────────────────────────────

  defp match_log2_plus_one(floor_call, one) do
    with true <- is_one?(one),
         {:floor, _, [{:/, _, [log_a, log_b]}]} <- floor_call,
         true <- is_math_log_2?(log_b) do
      extract_math_log_var(log_a)
    else
      _ -> :no
    end
  end

  defp is_one?({:__block__, _, [1]}), do: true
  defp is_one?(_), do: false

  defp is_math_log_2?({{:., _, [{:__block__, _, [:math]}, :log]}, _, [{:__block__, _, [2]}]}),
    do: true

  defp is_math_log_2?({{:., _, [{:__aliases__, _, [:math]}, :log]}, _, [{:__block__, _, [2]}]}),
    do: true

  defp is_math_log_2?(_), do: false

  defp extract_math_log_var({{:., _, [{:__block__, _, [:math]}, :log]}, _, [var]}),
    do: unwrap_var(var)

  defp extract_math_log_var({{:., _, [{:__aliases__, _, [:math]}, :log]}, _, [var]}),
    do: unwrap_var(var)

  defp extract_math_log_var(_), do: :no

  defp unwrap_var({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: {:ok, {name, [], ctx}}
  defp unwrap_var(_), do: :no

  # ── Replacement AST ──────────────────────────────────────────────

  defp build_integer_to_binary_pipe(var) do
    int_to_bin = {{:., [], [:erlang, :integer_to_binary]}, [], [{:__block__, [], [2]}]}
    pipe1 = {:|>, [newlines: 1], [var, int_to_bin]}
    length_call = {{:., [], [{:__aliases__, [], [:String]}, :length]}, [], []}
    {:|>, [newlines: 1], [pipe1, length_call]}
  end

  # ── Issue ─────────────────────────────────────────────────────────

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_integer_to_binary_for_bit_length,
      message:
        "Use `:erlang.integer_to_binary(n, 2) |> String.length()` for bit-length " <>
          "computation instead of floating-point `:math.log/1` arithmetic.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
