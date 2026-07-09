defmodule Credence.Semantic.NoEarlyReturnInUnless do
  @moduledoc """
  Fixes Python-style early-return patterns that cause `undefined function
  return/1` compiler errors.

  LLMs frequently write either of:

      unless condition do
        return {:error, reason}
      end
      rest_of_body

  or

      if condition do
        return {:error, reason}
      end
      rest_of_body

  Since `return/1` does not exist in Elixir, this fails to compile. The fix
  restructures the block into a single `if/else`, moving the return value
  into the `else` branch and `rest_of_body` into the `do` branch:

      if condition do
        rest_of_body
      else
        {:error, reason}
      end

  For `unless`, the guard is inverted. For `if`, the guard is kept as-is.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "undefined function return/"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_early_return_in_unless,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      result =
        Macro.prewalk(ast, fn
          {kind, meta, [fn_head, body_kw]} = node when kind in [:def, :defp] ->
            case transform_def_body(body_kw) do
              {:ok, new_body_kw} -> {kind, meta, [fn_head, new_body_kw]}
              :error -> node
            end

          node ->
            node
        end)

      if result == ast do
        source
      else
        Sourceror.to_string(result)
      end
    else
      _ -> source
    end
  end

  # The def body keyword list: [{{:__block__, _, [:do]}, body}]
  defp transform_def_body([{{:__block__, do_meta, [:do]}, body}]) do
    case transform_body(body) do
      {:ok, new_body} -> {:ok, [{{:__block__, do_meta, [:do]}, new_body}]}
      :error -> :error
    end
  end

  defp transform_def_body(_), do: :error

  # Multi-statement body: unless/return or if/return is the first statement, rest follows
  defp transform_body({:__block__, _meta, [early_return_node | rest]}) when rest != [] do
    with {:ok, condition, return_value, meta} <- extract_early_return(early_return_node) do
      do_body =
        case rest do
          [single] -> single
          multiple -> {:__block__, [], multiple}
        end

      # Reuse the original node's metadata (:do/:end/:line/:column) so Sourceror
      # renders block-style if/end rather than inline do:/else:.
      {:ok,
       {:if, meta,
        [
          condition,
          [
            {{:__block__, [], [:do]}, do_body},
            {{:__block__, [], [:else]}, return_value}
          ]
        ]}}
    else
      _ -> :error
    end
  end

  defp transform_body(_), do: :error

  # Match: unless cond do return value end (inverts the guard)
  # In Sourceror AST: {:unless, meta, [condition, [{{:__block__, _, [:do]}, {:return, _, [value]}}]]}
  defp extract_early_return({:unless, unless_meta, [condition, [{{:__block__, _, [:do]}, body}]]}) do
    case body do
      {:return, _, [value]} -> {:ok, condition, value, unless_meta}
      _ -> :error
    end
  end

  # Match: if cond do return value end (keeps the guard as-is)
  # In Sourceror AST: {:if, meta, [condition, [{{:__block__, _, [:do]}, {:return, _, [value]}}]]}
  defp extract_early_return({:if, if_meta, [condition, [{{:__block__, _, [:do]}, body}]]}) do
    case body do
      {:return, _, [value]} -> {:ok, condition, value, if_meta}
      _ -> :error
    end
  end

  defp extract_early_return(_), do: :error

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
