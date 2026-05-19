defmodule Credence.Pattern.NoIdentityFunctionInEnum do
  @moduledoc """
  Detects `Enum._by` functions called with an identity function callback,
  which can be simplified to the non-`_by` variant.

  LLMs sometimes generate `Enum.uniq_by(fn x -> x end)` instead of
  the simpler `Enum.uniq()`. This pattern appears across all `_by`
  variants.

  ## Bad

      list |> Enum.uniq_by(fn x -> x end)
      list |> Enum.sort_by(& &1)
      Enum.min_by(list, fn item -> item end)
      Enum.max_by(list, &Function.identity/1)

  ## Good

      list |> Enum.uniq()
      list |> Enum.sort()
      Enum.min(list)
      Enum.max(list)

  ## Auto-fix

  Rewrites `Enum.uniq_by(list, identity)` to `Enum.uniq(list)` and
  the piped form `|> Enum.uniq_by(identity)` to `|> Enum.uniq()`.
  Handles `fn x -> x end`, `& &1`, and `&(&1)` as identity functions.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @by_to_simple %{
    uniq_by: :uniq,
    sort_by: :sort,
    min_by: :min,
    max_by: :max,
    dedup_by: :dedup
  }

  @by_funcs Map.keys(@by_to_simple)

  @impl true
  def priority, do: 499

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Direct: Enum.func_by(list, identity)
        {{:., _, [{:__aliases__, _, [:Enum]}, func]}, meta, [_list, callback]} = node, acc
        when func in @by_funcs ->
          if identity_fn?(callback) do
            {node, [build_issue(meta, func) | acc]}
          else
            {node, acc}
          end

        # Piped: list |> Enum.func_by(identity)
        {:|>, _, [_lhs, {{:., _, [{:__aliases__, _, [:Enum]}, func]}, meta, [callback]}]} = node,
        acc
        when func in @by_funcs ->
          if identity_fn?(callback) do
            {node, [build_issue(meta, func) | acc]}
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
    {_ast, patches} =
      Macro.prewalk(ast, [], fn
        # Direct: Enum.func_by(list, identity)
        {{:., _, [{:__aliases__, _, [:Enum]}, func]}, _meta, [list, callback]} = node, acc
        when func in @by_funcs ->
          if identity_fn?(callback) do
            {node, [direct_patch(node, list, func) | acc]}
          else
            {node, acc}
          end

        # Piped: list |> Enum.func_by(identity). Patch only the RHS call,
        # leaving the `|>` and the LHS source byte-identical.
        {:|>, _, [_lhs, {{:., _, [{:__aliases__, _, [:Enum]}, func]}, _meta, [callback]} = rhs]} =
            node,
        acc
        when func in @by_funcs ->
          if identity_fn?(callback) do
            {node, [piped_patch(rhs, func) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(patches)
  end

  defp direct_patch(node, list, func) do
    simple = Map.fetch!(@by_to_simple, func)
    list_text = Sourceror.to_string(list)

    %{
      range: Sourceror.get_range(node),
      change: "Enum.#{simple}(#{list_text})"
    }
  end

  defp piped_patch(rhs_node, func) do
    simple = Map.fetch!(@by_to_simple, func)

    %{
      range: Sourceror.get_range(rhs_node),
      change: "Enum.#{simple}()"
    }
  end

  # fn x -> x end (single-clause, same variable in arg and body)
  defp identity_fn?({:fn, _, [{:->, _, [[{var, _, ctx}], {var, _, ctx}]}]})
       when is_atom(var) and is_atom(ctx),
       do: true

  # & &1
  defp identity_fn?({:&, _, [{:&, _, [1]}]}), do: true

  # &(&1)
  defp identity_fn?({:&, _, [{:&, _, [{:__block__, _, [1]}]}]}), do: true

  # &Function.identity/1
  defp identity_fn?(
         {:&, _,
          [
            {:/, _,
             [
               {{:., _, [{:__aliases__, _, [:Function]}, :identity]}, _, []},
               1
             ]}
          ]}
       ),
       do: true

  # &Function.identity/1 with __block__-wrapped 1
  defp identity_fn?(
         {:&, _,
          [
            {:/, _,
             [
               {{:., _, [{:__aliases__, _, [:Function]}, :identity]}, _, []},
               {:__block__, _, [1]}
             ]}
          ]}
       ),
       do: true

  defp identity_fn?(_), do: false

  defp build_issue(meta, func) do
    simple = Map.get(@by_to_simple, func)

    %Issue{
      rule: :no_identity_function_in_enum,
      message: """
      `Enum.#{func}/2` with an identity function is equivalent to \
      `Enum.#{simple}/1`.

      Simplify:

          Enum.#{simple}(list)
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
