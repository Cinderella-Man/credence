defmodule Credence.Rule.NoDocFalseOnPrivate do
  @moduledoc """
  Style rule: Detects `@doc false` placed before private functions (`defp`).

  Private functions cannot have documentation — the compiler ignores `@doc`
  on `defp` entirely. Adding `@doc false` is redundant noise that misleads
  readers into thinking it's suppressing something.

  ## Bad

      @doc false
      defp helper(x), do: x + 1

  ## Good

      defp helper(x), do: x + 1

      # If you want to hide a public function from docs:
      @doc false
      def internal_api(x), do: x + 1
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:__block__, _, stmts} = node, issues when is_list(stmts) ->
          new_issues =
            stmts
            |> Enum.chunk_every(2, 1, :discard)
            |> Enum.reduce(issues, fn
              [{:@, meta, [{:doc, _, [false]}]}, {:defp, _, _}], acc ->
                [build_issue(meta) | acc]

              [{:@, meta, [{:doc, _, [false]}]}, {:defp, _, [{:when, _, _} | _]}], acc ->
                [build_issue(meta) | acc]

              _, acc ->
                acc
            end)

          {node, new_issues}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_doc_false_on_private,
      severity: :info,
      message:
        "`@doc false` before `defp` is redundant — private functions cannot have documentation. " <>
          "Remove the `@doc false` annotation.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
