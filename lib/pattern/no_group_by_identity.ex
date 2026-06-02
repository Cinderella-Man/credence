defmodule Credence.Pattern.NoGroupByIdentity do
  @moduledoc """
  Check-only rule: Detects `Enum.group_by(enum, & &1)` which groups
  identical elements into lists.

  When you only need occurrence counts (e.g. to filter by frequency),
  `Enum.frequencies/1` (Elixir 1.10+) returns a `%{value => count}` map
  directly — no intermediate lists per group, clearer intent.

  When followed by `Map.filter` checking value-list lengths, the whole
  pipeline is a frequency filter that `Enum.frequencies/1` handles in
  fewer allocations.

  ## Flagged

      Enum.group_by(list, & &1)
      Enum.group_by(list, fn x -> x end)

  ## Better

      Enum.frequencies(list)

  ## No auto-fix

  Replacement depends on downstream usage (counts vs grouped elements),
  so this rule only flags — no automatic rewrite.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Piped: ... |> Enum.group_by(& &1)
        {:|>, _meta, [_left, group_by_call]} = node, issues ->
          if identity_group_by_piped?(group_by_call) do
            {node, [build_issue(extract_meta(group_by_call)) | issues]}
          else
            {node, issues}
          end

        # Direct: Enum.group_by(enum, & &1)
        {{:., _, [{:__aliases__, _, [:Enum]}, :group_by]}, _meta, [_enum, cb]} = node, issues ->
          if identity_fn?(cb) do
            {node, [build_issue(extract_meta(node)) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # Piped form: Enum.group_by(& &1) — only one arg (the callback)
  defp identity_group_by_piped?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :group_by]}, _meta, [cb]}
       ),
       do: identity_fn?(cb)

  defp identity_group_by_piped?(_), do: false

  # & &1
  defp identity_fn?({:&, _, [{:&, _, [1]}]}), do: true
  # &(&1) — Sourceror wraps the 1 in __block__
  defp identity_fn?({:&, _, [{:&, _, [{:__block__, _, [1]}]}]}), do: true
  # fn x -> x end
  defp identity_fn?({:fn, _, [{:->, _, [[{var, _, ctx}], {var, _, ctx}]}]})
       when is_atom(var) and is_atom(ctx),
       do: true

  defp identity_fn?(_), do: false

  defp extract_meta({{:., meta, _}, _, _}), do: meta
  defp extract_meta(_), do: []

  defp build_issue(meta) do
    %Issue{
      rule: :no_group_by_identity,
      message:
        "`Enum.group_by(enum, & &1)` groups identical elements into lists. " <>
          "When you only need occurrence counts, use `Enum.frequencies/1` instead — " <>
          "it returns a `%{value => count}` map with no intermediate lists per group.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
