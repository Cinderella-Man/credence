defmodule Credence.Pattern.PreferStringFirstLast do
  @moduledoc """
  Detects the anti-pattern of using `String.split_at/2` to extract the first
  character via a `case` destructuring, then comparing it with `String.last/1`.
  This can be replaced with the more idiomatic `String.first/1 == String.last/1`.

  ## Bad

      case String.split_at(string, 1) do
        {first_char, _rest} ->
          last_char = String.last(string)
          first_char == last_char
      end

  ## Good

      String.first(string) == String.last(string)
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:case, meta, [_subject, kw]} = node, acc when is_list(kw) ->
          case extract_anti_pattern(kw) do
            {:ok, _string_var} -> {node, [build_issue(meta) | acc]}
            :error -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {:case, _meta, [_subject, kw]} = node ->
        case extract_anti_pattern(kw) do
          {:ok, string_var} ->
            build_replacement(string_var)

          :error ->
            node
        end

      node ->
        node
    end)
  end

  # Matches the anti-pattern in the case expression's do-block.
  # Returns {:ok, string_var} if matched, :error otherwise.
  defp extract_anti_pattern(kw) do
    with [{{:__block__, _, [:do]}, [clause]}] <- kw,
         {:->, _, [[{:__block__, _, [{{first_var, _, nil}, {_, _, nil}}]}], body]} <- clause,
         {:__block__, _, [assign_stmt, compare_stmt]} <- body,
         {:=, _, [{last_var, _, nil}, split_at_call]} <- assign_stmt,
         {{:., _, [{:__aliases__, _, [:String]}, :last]}, _, [{string_var, _, nil}]} <-
           split_at_call,
         {:==, _, [{^first_var, _, nil}, {^last_var, _, nil}]} <- compare_stmt do
      {:ok, string_var}
    else
      _ -> :error
    end
  end

  # Builds the replacement AST: String.first(string) == String.last(string)
  defp build_replacement(string_var) do
    string_ref = {string_var, [], nil}

    {:==, [],
     [
       build_remote_call(:String, :first, [string_ref]),
       build_remote_call(:String, :last, [string_ref])
     ]}
  end

  defp build_remote_call(mod, fun, args) do
    {{:., [], [{:__aliases__, [], [mod]}, fun]}, [], args}
  end

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_string_first_last,
      message:
        "Use `String.first/1` and `String.last/1` directly instead of " <>
          "`String.split_at/2` with a case destructuring to extract the first character.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
