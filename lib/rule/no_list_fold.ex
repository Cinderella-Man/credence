defmodule Credence.Rule.NoListFold do
  @moduledoc """
  Detects usage of `List.foldl/3` and `List.foldr/3` and suggests
  `Enum.reduce/3` instead.

  ## Why this matters

  `Enum.reduce/3` is the idiomatic Elixir way to fold over a collection.
  While `List.foldl/3` and `List.foldr/3` exist in Elixir's standard
  library, they are rarely used in practice and signal code ported from
  Erlang (`:lists.foldl`) or Haskell.

  LLMs frequently generate `List.foldl` because their training data
  includes heavy Erlang and Haskell influence. The resulting code is
  functionally correct but non-idiomatic, which reduces readability for
  Elixir developers.

  ## Flagged patterns

  | Pattern              | Suggested replacement   |
  | -------------------- | ----------------------- |
  | `List.foldl/3`       | `Enum.reduce/3`         |
  | `List.foldr/3`       | `Enum.reduce/3` (with note about reversal) |
  """

  @behaviour Credence.Rule
  alias Credence.Issue

  @flagged_fns [:foldl, :foldr]

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case extract_list_fold(node) do
          {:ok, fn_name, meta} ->
            issue = %Issue{
              rule: :no_list_fold,
              message: build_message(fn_name),
              meta: %{line: Keyword.get(meta, :line)}
            }

            {node, [issue | issues]}

          :error ->
            {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  # ------------------------------------------------------------
  # DETECTION
  #
  # Matches fully-qualified calls: List.foldl(...) / List.foldr(...)
  # in the AST form produced by Code.string_to_quoted/1.
  # ------------------------------------------------------------

  # Dot-call form: List.foldl(list, acc, fun)
  defp extract_list_fold({{:., meta, [mod, fn_name]}, _, args})
       when fn_name in @flagged_fns and is_list(args) do
    if list_module?(mod), do: {:ok, fn_name, meta}, else: :error
  end

  defp extract_list_fold(_), do: :error

  # ------------------------------------------------------------
  # MESSAGE GENERATION
  # ------------------------------------------------------------

  defp build_message(:foldl) do
    """
    `List.foldl/3` is not idiomatic Elixir.

    Use `Enum.reduce/3` instead — it is the standard way to
    fold over a collection:

        Enum.reduce(list, acc, fn elem, acc -> ... end)
    """
  end

  defp build_message(:foldr) do
    """
    `List.foldr/3` is not idiomatic Elixir.

    Use `Enum.reduce/3` instead. If right-fold order is needed,
    reverse the list first:

        list |> Enum.reverse() |> Enum.reduce(acc, fun)
    """
  end

  # ------------------------------------------------------------
  # HELPERS
  # ------------------------------------------------------------

  defp list_module?({:__aliases__, _, [:List]}), do: true
  defp list_module?(_), do: false
end
