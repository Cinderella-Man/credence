defmodule Credence.Pattern.NoFindValueDefaultCase do
  @moduledoc """
  Detects `Enum.find_value/2` where the result is immediately checked
  against `nil` to provide a default, instead of using the 3-arity
  version that accepts a default argument.

  ## Bad

      case Enum.find_value(list, &process/1) do
        nil -> :default
        val -> val
      end

      Enum.find_value(list, &process/1) || :default

  ## Good

      Enum.find_value(list, :default, &process/1)

  ## Auto-fix

  Replaces the `case`/`||` wrapper with the 3-arity call.

  ## Safety

  This rule is deliberately limited to `Enum.find_value`, and (for the
  `case` form) only when the `nil ->` clause comes **first**. The reason
  is that the rewrite must give the exact same answer for every input:

    * `Enum.find/2` is **not** covered. `find/2` returns the matching
      *element*, which can itself be `nil` (or `false`). A genuinely
      found `nil` element would be treated as "not found" by both the
      `case nil ->` clause and by `Enum.find/3` differently
      (`find/3` returns the found `nil`, the `case` returns the default),
      so the answers diverge. `find_value` only ever returns a *truthy*
      value or `nil`, so `nil` unambiguously means "nothing found".

    * The identity clause must come *after* the `nil ->` clause. If it
      comes first (`val -> val; nil -> d`) it matches `nil` too, making
      the `nil ->` clause dead code — the expression then returns `nil`
      (never the default), so rewriting to `/3` would change the answer.

    * `||` is safe only for `find_value` (its result is never `false`).
      `Enum.find/2 || default` is not covered: a found `false`/`nil`
      element is falsy and would wrongly fall through to the default.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # case Enum.find_value(coll, fun) do nil -> d; v -> v end
        {:case, meta, [find_call, kw]} = node, acc when is_list(kw) ->
          if find2?(find_call) and nil_identity?(kw) do
            {node, [build_issue(:case, meta, find_call) | acc]}
          else
            {node, acc}
          end

        # coll |> Enum.find_value(fun) |> case do nil -> d; v -> v end
        # (must precede the 2-arg pipe clause below, which would otherwise
        # match this shape with find_call bound to the inner pipe)
        {:|>, _,
         [
           {:|>, _, [_coll, find1_call]},
           {:case, meta, [kw]}
         ]} = node,
        acc
        when is_list(kw) ->
          if find1?(find1_call) and nil_identity?(kw) do
            {node, [build_issue(:case, meta, find1_call) | acc]}
          else
            {node, acc}
          end

        # Enum.find_value(coll, fun) |> case do nil -> d; v -> v end
        {:|>, _, [find_call, {:case, meta, [kw]}]} = node, acc when is_list(kw) ->
          if find2?(find_call) and nil_identity?(kw) do
            {node, [build_issue(:case, meta, find_call) | acc]}
          else
            {node, acc}
          end

        # Enum.find_value(coll, fun) || default
        {:||, meta, [find_call, _default]} = node, acc ->
          if find2?(find_call) do
            {node, [build_issue(:or, meta, find_call) | acc]}
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
      # case Enum.find_value(coll, fun) do nil -> d; v -> v end
      {:case, _, [find_call, kw]} = node ->
        if find2?(find_call) and nil_identity?(kw) do
          rewrite_2arg(find_call, extract_default(kw))
        else
          node
        end

      # coll |> Enum.find_value(fun) |> case do nil -> d; v -> v end
      # (must precede the 2-arg pipe clause below)
      {:|>, _, [{:|>, _, [coll, find1_call]}, {:case, _, [kw]}]} = node ->
        if find1?(find1_call) and nil_identity?(kw) do
          rewrite_1arg_pipe(coll, find1_call, extract_default(kw))
        else
          node
        end

      # Enum.find_value(coll, fun) |> case do nil -> d; v -> v end
      {:|>, _, [find_call, {:case, _, [kw]}]} = node ->
        if find2?(find_call) and nil_identity?(kw) do
          rewrite_2arg(find_call, extract_default(kw))
        else
          node
        end

      # Enum.find_value(coll, fun) || default
      {:||, _, [find_call, default]} = node ->
        if find2?(find_call) do
          rewrite_2arg(find_call, default)
        else
          node
        end

      node ->
        node
    end)
  end

  # ── Matchers ───────────────────────────────────────────────────────────

  defp find2?({{:., _, [{:__aliases__, _, [:Enum]}, :find_value]}, _, [_, _]}), do: true
  defp find2?(_), do: false

  defp find1?({{:., _, [{:__aliases__, _, [:Enum]}, :find_value]}, _, [_]}), do: true
  defp find1?(_), do: false

  # ── Case clause checks ─────────────────────────────────────────────────

  # Only the safe ordering: `nil ->` clause first, identity clause second.
  defp nil_identity?(kw) do
    case do_clauses(kw) do
      [c1, c2] -> nil_clause?(c1) and identity?(c2)
      _ -> false
    end
  end

  defp do_clauses([{{:__block__, _, [:do]}, clauses}]) when is_list(clauses), do: clauses
  defp do_clauses(_), do: nil

  defp nil_clause?({:->, _, [[{:__block__, _, [nil]}], _]}), do: true
  defp nil_clause?({:->, _, [[nil], _]}), do: true
  defp nil_clause?(_), do: false

  defp identity?({:->, _, [[{name, _, ctx}], {name2, _, ctx2}]})
       when is_atom(name) and is_atom(name2) and name == name2 and
              (is_nil(ctx) or is_atom(ctx)) and (is_nil(ctx2) or is_atom(ctx2)),
       do: true

  defp identity?(_), do: false

  # ── Extractors ─────────────────────────────────────────────────────────

  defp extract_default(kw) do
    do_clauses(kw)
    |> Enum.find_value(fn
      {:->, _, [[{:__block__, _, [nil]}], body]} -> body
      {:->, _, [[nil], body]} -> body
      _ -> nil
    end)
  end

  # ── Rewriters ──────────────────────────────────────────────────────────

  defp rewrite_2arg(
         {{:., dm, [{:__aliases__, am, [:Enum]}, func]}, cm, [coll, fun]},
         default
       ) do
    {{:., dm, [{:__aliases__, am, [:Enum]}, func]}, cm, [coll, default, fun]}
  end

  defp rewrite_1arg_pipe(
         coll,
         {{:., dm, [{:__aliases__, am, [:Enum]}, func]}, cm, [fun]},
         default
       ) do
    {{:., dm, [{:__aliases__, am, [:Enum]}, func]}, cm, [coll, default, fun]}
  end

  # ── Issue builders ─────────────────────────────────────────────────────

  defp build_issue(:case, meta, find_call) do
    {{:., _, [{:__aliases__, _, [:Enum]}, func]}, _, _} = find_call

    %Issue{
      rule: :no_find_value_default_case,
      message:
        "`case Enum.#{func}/2 do nil -> default; val -> val end` should use " <>
          "`Enum.#{func}/3` with the default as the second argument.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp build_issue(:or, meta, find_call) do
    {{:., _, [{:__aliases__, _, [:Enum]}, func]}, _, _} = find_call

    %Issue{
      rule: :no_find_value_default_case,
      message:
        "`Enum.#{func}/2 || default` should use " <>
          "`Enum.#{func}/3` with the default as the second argument.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
