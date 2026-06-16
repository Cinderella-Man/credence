defmodule Credence.Pattern.PreferConcatOverFlatMapIdentity do
  @moduledoc """
  Detects `Enum.flat_map(enumerable, fn x -> x end)` which is an identity
  flat-map and can be simplified to `Enum.concat(enumerable)`.

  LLMs sometimes generate `Enum.flat_map(fn x -> x end)` instead of the
  simpler `Enum.concat/1`. This pattern also appears in piped form.

  ## Bad

      matrix |> Enum.flat_map(fn row -> row end)
      Enum.flat_map(list_of_lists, fn x -> x end)

  ## Good

      Enum.concat(matrix)
      Enum.concat(list_of_lists)
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Direct: Enum.flat_map(list, identity_fn)
        {{:., _, [{:__aliases__, _, [:Enum]}, :flat_map]}, meta, [_list, callback]} = node, acc ->
          if identity_fn?(callback) do
            {node, [build_issue(meta) | acc]}
          else
            {node, acc}
          end

        # Piped: list |> Enum.flat_map(identity_fn)
        {:|>, _, [_lhs, {{:., _, [{:__aliases__, _, [:Enum]}, :flat_map]}, meta, [callback]}]} =
            node,
        acc ->
          if identity_fn?(callback) do
            {node, [build_issue(meta) | acc]}
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
        # Direct: Enum.flat_map(list, identity_fn)
        {{:., _, [{:__aliases__, _, [:Enum]}, :flat_map]}, _meta, [list, callback]} = node, acc ->
          if identity_fn?(callback) do
            {node, [direct_patch(node, list) | acc]}
          else
            {node, acc}
          end

        # Piped: list |> Enum.flat_map(identity_fn). Patch only the RHS call,
        # leaving the `|>` and the LHS source byte-identical.
        {:|>, _,
         [_lhs, {{:., _, [{:__aliases__, _, [:Enum]}, :flat_map]}, _meta, [callback]} = rhs]} =
            node,
        acc ->
          if identity_fn?(callback) do
            {node, [piped_patch(rhs) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(patches)
  end

  defp direct_patch(node, list) do
    list_text = Sourceror.to_string(list)

    %{
      range: Sourceror.get_range(node),
      change: "Enum.concat(#{list_text})"
    }
  end

  defp piped_patch(rhs_node) do
    %{
      range: Sourceror.get_range(rhs_node),
      change: "Enum.concat()"
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
         {:&,
          [
            {:/, _,
             [
               {{:., _, [{:__aliases__, [:Function]}, :identity]}, _, []},
               1
             ]}
          ]}
       ),
       do: true

  # &Function.identity/1 with __block__-wrapped 1
  defp identity_fn?(
         {:&,
          [
            {:/, _,
             [
               {{:., _, [{:__aliases__, [:Function]}, :identity]}, _, []},
               {:__block__, _, [1]}
             ]}
          ]}
       ),
       do: true

  defp identity_fn?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_concat_over_flat_map_identity,
      message: """
      `Enum.flat_map/2` with an identity function is equivalent to `Enum.concat/1`.

      Simplify:

          Enum.concat(enumerable)
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
