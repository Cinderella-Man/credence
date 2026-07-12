defmodule Credence.Semantic.NoDiscardedUnlessValue do
  @moduledoc """
  Fixes `unless` blocks whose body value is silently discarded because
  the block is followed by another expression.

  LLMs frequently write early-return patterns as:

      unless condition do
        {:error, :invalid_sort_field}
      end

      {:ok, %{sort: sort, direction: direction}}

  After `no_bare_return_in_unless` strips the `return`, the `unless`
  block's value (`{:error, :invalid_sort_field}`) is computed but
  never returned — the final expression is always the block's return
  value. The fix restructures the `unless` + following expression into
  a single `if/else`:

      if not condition do
        {:error, :invalid_sort_field}
      else
        {:ok, %{sort: sort, direction: direction}}
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "unless expression result is unused"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_discarded_unless_value,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      result =
        Macro.prewalk(ast, fn
          {:__block__, meta, children} = node when is_list(children) ->
            case merge_discarded_unless(children) do
              {:ok, new_children} -> {:__block__, meta, new_children}
              :error -> node
            end

          node ->
            node
        end)

      if result == ast, do: source, else: Sourceror.to_string(result)
    else
      _ -> source
    end
  end

  # A block needs at least 2 children for a discarded unless to exist.
  defp merge_discarded_unless(children) when length(children) < 2, do: :error

  defp merge_discarded_unless(children) do
    children
    |> Enum.with_index()
    |> Enum.find_value(:error, fn
      {{:unless, _, [_, kw]} = unless_node, idx} when is_list(kw) ->
        if not has_else_branch?(kw) and idx < length(children) - 1 do
          {before, rest} = Enum.split(children, idx)
          [_unless | after_exprs] = rest
          new_if = unless_to_if(unless_node, after_exprs)
          {:ok, before ++ [new_if]}
        end

      _ ->
        nil
    end)
  end

  defp has_else_branch?(kw) do
    Enum.any?(kw, fn
      {{:__block__, _, [:else]}, _} -> true
      _ -> false
    end)
  end

  defp unless_to_if({:unless, meta, [condition, kw]}, after_exprs) do
    negated = {:not, [], [condition]}

    # Extract do body from the keyword list
    do_body =
      Enum.find_value(kw, fn
        {{:__block__, _, [:do]}, body} -> body
      end)

    # Build else body from the following expressions
    else_body =
      case after_exprs do
        [single] -> single
        multiple -> {:__block__, [], multiple}
      end

    # Build the new if/else node, reusing the unless metadata
    {:if, meta,
     [
       negated,
       [
         {{:__block__, [], [:do]}, do_body},
         {{:__block__, [], [:else]}, else_body}
       ]
     ]}
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
