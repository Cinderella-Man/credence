defmodule Credence.Semantic.NoBareReturnInUnless do
  @moduledoc """
  Removes bare `return` keyword from inside `unless` blocks that have an `else` branch.

  LLMs (trained on Python) frequently write:

      unless condition do
        return {:error, reason}
      else
        ...
      end

  Since `return/1` does not exist in Elixir, this fails to compile. The fix
  unwraps the `return` call, leaving just the value as the block's last
  expression:

      unless condition do
        {:error, reason}
      else
        ...
      end

  This rule only applies when the `unless` block has an `else` branch. For
  `unless` blocks without `else` (early-return patterns), see
  `NoEarlyReturnInUnless`.
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
      rule: :no_bare_return_in_unless,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      result =
        Macro.prewalk(ast, fn
          # Handle unless blocks with else: unwrap return in do branch
          {:unless, unless_meta, [condition, kw]} = node when is_list(kw) ->
            if has_else_branch?(kw) do
              new_kw = unwrap_return_in_do(kw)

              if new_kw != kw do
                {:unless, unless_meta, [condition, new_kw]}
              else
                node
              end
            else
              node
            end

          # Handle: if COND, do: return(VALUE)  followed by REST in a block
          # →  if COND do VALUE else REST end
          {:__block__, block_meta,
           [
             {:if, if_meta,
              [
                condition,
                [{{:__block__, do_meta, [:do]}, {:return, _, [value]}}]
              ]}
             | rest
           ]}
          when rest != [] and is_list(do_meta) ->
            if Keyword.get(do_meta, :format) == :keyword do
              rest_block =
                case rest do
                  [single] -> single
                  multiple -> {:__block__, [], multiple}
                end

              # Add do:/end: to metadata so Sourceror renders block form
              block_meta =
                if_meta
                |> Keyword.put_new(:do, do_meta |> Keyword.drop([:format]))
                |> Keyword.put_new(:end, do_meta |> Keyword.drop([:format]))

              {:if, block_meta,
               [
                 condition,
                 [
                   {{:__block__, [], [:do]}, value},
                   {{:__block__, [], [:else]}, rest_block}
                 ]
               ]}
            else
              {:__block__, block_meta,
               [
                 {:if, if_meta,
                  [
                    condition,
                    [{{:__block__, do_meta, [:do]}, {:return, [], [value]}}]
                  ]}
                 | rest
               ]}
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

  defp has_else_branch?(kw) do
    Enum.any?(kw, fn
      {{:__block__, _, [:else]}, _} -> true
      _ -> false
    end)
  end

  defp unwrap_return_in_do(kw) do
    Enum.map(kw, fn
      {{:__block__, meta, [:do]}, {:return, _, [value]}} ->
        {{:__block__, meta, [:do]}, value}

      other ->
        other
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
