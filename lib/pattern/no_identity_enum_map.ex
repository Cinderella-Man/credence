defmodule Credence.Pattern.NoIdentityEnumMap do
  @moduledoc """
  Detects `Enum.map/2` called with an identity function callback, which is just
  a verbose `Enum.to_list/1`.

  `Enum.map(enum, fn x -> x end)` walks the enumerable and rebuilds every
  element unchanged — the closure does nothing. The idiomatic spelling of
  "materialise this enumerable into a list" is `Enum.to_list/1`.

  ## Why `Enum.to_list/1` and not just the bare argument

  Dropping the call entirely (`Enum.map(enum, & &1)` → `enum`) is **not**
  behaviour-preserving: `Enum.map/2` always returns a list, so on a map it
  returns a keyword list, on a range a list, and on a non-enumerable (a bare
  string, an integer) it raises `Protocol.UndefinedError`. `Enum.to_list/1` has
  the identical contract on every one of those inputs, so the rewrite is safe
  with no assumptions. (A "delete it" rule would need to prove the argument is
  statically a list — see `no_enum_count_for_length` for that style.)

  ## Bad

      Enum.map(list, fn x -> x end)
      list |> Enum.map(& &1)
      Enum.map(enum, &Function.identity/1)

  ## Good

      Enum.to_list(list)
      list |> Enum.to_list()
      Enum.to_list(enum)

  ## Auto-fix

  Rewrites `Enum.map(enum, identity)` to `Enum.to_list(enum)` and the piped form
  `|> Enum.map(identity)` to `|> Enum.to_list()`. Handles `fn x -> x end`,
  `& &1`, `&(&1)`, and `&Function.identity/1` as identity functions.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  # Run LATE (after the default 500 band). This is a cleanup/normalisation:
  # collapsing the no-op closure must not pre-empt a more specific structural
  # rule that needs the raw `Enum.map` node — e.g. `no_map_then_aggregate` fuses
  # `Enum.map(x, & &1) |> Enum.sum()` into a reduce that `no_explicit_sum_reduce`
  # (501) then turns into `Enum.sum(x)`. Firing first would strand it as
  # `Enum.to_list(x) |> Enum.sum()`. Let those run, then mop up any standalone
  # identity map.
  @impl true
  def priority, do: 520

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Direct: Enum.map(enum, identity)
        {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, meta, [_enum, callback]} = node, acc ->
          if identity_fn?(callback) do
            {node, [build_issue(meta) | acc]}
          else
            {node, acc}
          end

        # Piped: enum |> Enum.map(identity)
        {:|>, _, [_lhs, {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, meta, [callback]}]} = node,
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
        # Direct: Enum.map(enum, identity)
        {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _meta, [enum, callback]} = node, acc ->
          if identity_fn?(callback) do
            {node, [direct_patch(node, enum) | acc]}
          else
            {node, acc}
          end

        # Piped: enum |> Enum.map(identity). Patch only the RHS call, leaving the
        # `|>` and the LHS source byte-identical.
        {:|>, _, [_lhs, {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _meta, [callback]} = rhs]} =
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

  defp direct_patch(node, enum) do
    enum_text = Sourceror.to_string(enum)

    %{
      range: Sourceror.get_range(node),
      change: "Enum.to_list(#{enum_text})"
    }
  end

  defp piped_patch(rhs_node) do
    %{
      range: Sourceror.get_range(rhs_node),
      change: "Enum.to_list()"
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

  defp build_issue(meta) do
    %Issue{
      rule: :no_identity_enum_map,
      message: """
      `Enum.map/2` with an identity function is equivalent to `Enum.to_list/1`.

      Simplify:

          Enum.to_list(enum)
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
