defmodule Credence.Rule.NoIdentityFunctionInEnum do
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

  use Credence.Rule
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
  def fixable?, do: true

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
  def fix(source, _opts) do
    source
    |> String.split("\n")
    |> Enum.map(&fix_line/1)
    |> Enum.join("\n")
  end

  # ── Identity function detection ─────────────────────────────────

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

  # ── Fix ─────────────────────────────────────────────────────────

  defp fix_line(line) do
    line
    |> fix_direct_call()
    |> fix_piped_call()
  end

  # Enum.func_by(arg, fn x -> x end) → Enum.func(arg)
  # Enum.func_by(arg, & &1) → Enum.func(arg)
  defp fix_direct_call(line) do
    Regex.replace(
      ~r/Enum\.(uniq_by|sort_by|min_by|max_by|dedup_by)\((.+),\s*(?:fn\s+(\w+)\s*->\s*\3\s*end|& &1|&\(&1\)|&Function\.identity\/1)\)/,
      line,
      fn _, func, arg, _ -> "Enum.#{simplify(func)}(#{String.trim(arg)})" end
    )
  end

  # |> Enum.func_by(fn x -> x end) → |> Enum.func()
  defp fix_piped_call(line) do
    Regex.replace(
      ~r/Enum\.(uniq_by|sort_by|min_by|max_by|dedup_by)\((?:fn\s+(\w+)\s*->\s*\2\s*end|& &1|&\(&1\)|&Function\.identity\/1)\)/,
      line,
      fn _, func -> "Enum.#{simplify(func)}()" end
    )
  end

  defp simplify(func) do
    @by_to_simple
    |> Map.get(String.to_existing_atom(func))
    |> Atom.to_string()
  end

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
