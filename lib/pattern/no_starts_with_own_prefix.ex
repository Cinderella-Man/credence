defmodule Credence.Pattern.NoStartsWithOwnPrefix do
  @moduledoc """
  Detects `String.starts_with?/2` calls where the prefix is a slice
  of the same string starting from index 0, making the check
  tautologically true.

  ## Why this matters

  A string always starts with its own prefix.  `String.starts_with?(x,
  String.slice(x, 0, n))` is always `true` for any non-negative `n`,
  yet LLMs emit this guard as a "safety check" in character-by-character
  string comparison loops.

  ## Flagged patterns

  | Pattern                                                | Why              |
  | ------------------------------------------------------ | ---------------- |
  | `String.starts_with?(x, String.slice(x, 0, n))`       | Always `true`    |

  ## Bad

      if String.starts_with?(common, String.slice(common, 0, idx + 1)) &&
           String.starts_with?(string, String.slice(common, 0, idx + 1)) do
        ...
      end

  ## Good

      if String.starts_with?(string, String.slice(common, 0, idx + 1)) do
        ...
      end
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case check_tautological_starts_with(node) do
          {:ok, meta} ->
            issue = %Issue{
              rule: :no_starts_with_own_prefix,
              message: """
              `String.starts_with?(x, String.slice(x, 0, _))` is always true.
              A string always starts with its own prefix. Remove this tautological \
              check or replace the entire condition with the remaining non-trivial part.
              """,
              meta: %{line: Keyword.get(meta, :line)}
            }

            {node, [issue | issues]}

          :error ->
            {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # String.starts_with?(x, String.slice(x, 0, n))
  # where both x references are the same variable.
  defp check_tautological_starts_with(
         {{:., meta, [{:__aliases__, _, [:String]}, :starts_with?]}, _,
          [
            subject,
            {{:., _, [{:__aliases__, _, [:String]}, :slice]}, _,
             [slice_subject, slice_start, _len]}
          ]}
       ) do
    if literal_zero?(slice_start) and same_variable?(subject, slice_subject) do
      {:ok, meta}
    else
      :error
    end
  end

  defp check_tautological_starts_with(_), do: :error

  defp literal_zero?(0), do: true
  defp literal_zero?({:__block__, _, [0]}), do: true
  defp literal_zero?(_), do: false

  defp same_variable?({name, _, ctx}, {name, _, ctx})
       when is_atom(name) and is_atom(ctx),
       do: true

  defp same_variable?(_, _), do: false
end
