defmodule Credence.Pattern.PreferStringAtForCharAccess do
  @moduledoc """
  Detects the anti-pattern of converting a single-character binary variable
  to a charlist, extracting the head (codepoint integer), storing it in an
  intermediate variable, then later converting that integer back to a string
  with `List.to_string([codepoint])`.

  The `List.to_string([codepoint])` call is redundant: `<<codepoint::utf8>`
  produces the same binary more idiomatically, and can be used directly inside
  string interpolation without the intermediate variable.

  ## Bad

      col_start_code = col_start |> String.to_charlist() |> hd()
      ...
      for col_code <- col_start_code..col_end_code, ... do
        col_letter = List.to_string([col_code])
        "\#{col_letter}\#{row}"
      end

  ## Good

      col_start_code = col_start |> String.to_charlist() |> hd()
      ...
      for col_code <- col_start_code..col_end_code, ... do
        "\#{<<col_code::utf8>>}\#{row}"
      end
  """
  use Credence.Pattern.Rule
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        node, issues ->
          case match_list_to_string(node) do
            {:ok, _body_var, _code_var} ->
              {node, [build_issue(node) | issues]}

            :error ->
              {node, issues}
          end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)
    RuleHelpers.patches_from_ast_transform(ast, source, &transform_ast/1)
  end

  defp transform_ast(ast) do
    Macro.postwalk(ast, fn
      {:__block__, _meta, stmts} = node when is_list(stmts) ->
        case rewrite_block(stmts) do
          {:changed, new_stmts} -> {:__block__, [], new_stmts}
          :unchanged -> node
        end

      node ->
        node
    end)
  end

  defp rewrite_block(stmts) do
    # Find all `body_var = List.to_string([code_var])` assignments
    to_remove_and_replace =
      stmts
      |> Enum.reduce(%{}, fn stmt, acc ->
        case match_list_to_string(stmt) do
          {:ok, body_var, code_var} -> Map.put(acc, body_var, code_var)
          :error -> acc
        end
      end)

    if map_size(to_remove_and_replace) > 0 do
      remove_set = Map.keys(to_remove_and_replace) |> MapSet.new()

      new_stmts =
        stmts
        |> Enum.reject(fn stmt ->
          case stmt do
            {:=, _, [{var, _, nil}, _]} -> MapSet.member?(remove_set, var)
            _ -> false
          end
        end)
        |> Enum.map(fn stmt ->
          replace_body_vars(stmt, to_remove_and_replace)
        end)

      {:changed, new_stmts}
    else
      :unchanged
    end
  end

  # Match: body_var = List.to_string([code_var])
  defp match_list_to_string(
         {:=, _,
          [
            {body_var, _, nil},
            {{:., _, [{:__aliases__, _, [:List]}, :to_string]}, _,
             [{:__block__, _, [[{code_var, _, nil}]]}]}
          ]}
       )
       when is_atom(body_var) and is_atom(code_var) do
    {:ok, body_var, code_var}
  end

  defp match_list_to_string(_), do: :error

  # Replace `body_var` with `<<code_var::utf8>>` throughout the AST
  defp replace_body_vars(stmt, replacement_map) do
    Macro.prewalk(stmt, fn
      {var, meta, nil} = node when is_atom(var) ->
        case Map.get(replacement_map, var) do
          nil ->
            node

          code_var ->
            # Build `<<code_var::utf8>>` AST
            {:<<>>, [line: Keyword.get(meta, :line)],
             [
               {:"::", [],
                [
                  {code_var, [], nil},
                  {:utf8, [], nil}
                ]}
             ]}
        end

      node ->
        node
    end)
  end

  defp build_issue(node) do
    meta =
      case node do
        {_, m, _} when is_list(m) -> m
        _ -> []
      end

    %Issue{
      rule: :prefer_string_at_for_char_access,
      message:
        "Avoid the redundant `List.to_string([codepoint])` call. " <>
          "Use `<<codepoint::utf8>>` instead — it creates the same binary " <>
          "more idiomatically and can be used directly in string interpolation.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
