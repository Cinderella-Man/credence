defmodule Credence.Pattern.PreferStringSliceForTrimLastChar do
  @moduledoc """
  Detects the verbose `case String.graphemes(str)` idiom for removing the
  last character from a string, and rewrites it to the idiomatic
  `String.slice(str, 0..-2//1)`.

  ## Bad

      case String.graphemes(str) do
        [] -> ""
        [_last] -> ""
        [_head | _tail] -> String.slice(str, 0, String.length(str) - 1)
      end

  ## Good

      String.slice(str, 0..-2//1)
  """
  use Credence.Pattern.Rule
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        node, issues ->
          case match_trim_last_char(node) do
            {:ok, _var} ->
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
      node ->
        case match_trim_last_char(node) do
          {:ok, var} ->
            build_replacement(var)

          :error ->
            node
        end
    end)
  end

  # Match: case String.graphemes(var) do
  #          [] -> ""
  #          [_last] -> ""
  #          [_head | _tail] -> String.slice(var, 0, String.length(var) - 1)
  #        end
  defp match_trim_last_char({:case, _meta, [subject, clauses_kw]}) do
    with {:ok, var} <- match_graphemes_subject(subject),
         {:ok, clauses} <- extract_do_clauses(clauses_kw),
         true <- length(clauses) == 3,
         true <- match_empty_clause?(Enum.at(clauses, 0)),
         true <- match_single_clause?(Enum.at(clauses, 1)),
         true <- match_head_tail_clause?(Enum.at(clauses, 2), var) do
      {:ok, var}
    else
      _ -> :error
    end
  end

  defp match_trim_last_char(_), do: :error

  # Match: String.graphemes(var)
  defp match_graphemes_subject(
         {{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, [{var, _, nil}]}
       )
       when is_atom(var) do
    {:ok, var}
  end

  defp match_graphemes_subject(_), do: :error

  # Extract clauses from the do block
  defp extract_do_clauses([{{:__block__, _, [:do]}, clauses}]) when is_list(clauses) do
    {:ok, clauses}
  end

  defp extract_do_clauses(_), do: :error

  # Match: [] -> ""
  defp match_empty_clause?({:->, _, [[{:__block__, _, [[]]}], {:__block__, _, [""]}]}) do
    true
  end

  defp match_empty_clause?(_), do: false

  # Match: [_last] -> ""
  defp match_single_clause?(
         {:->, _,
          [
            [
              {:__block__, _, [[{var, _, nil}]]}
            ],
            {:__block__, _, [""]}
          ]}
       )
       when is_atom(var) do
    true
  end

  defp match_single_clause?(_), do: false

  # Match: [_head | _tail] -> String.slice(var, 0, String.length(var) - 1)
  defp match_head_tail_clause?(
         {:->, _,
          [
            [
              {:__block__, _,
               [
                 [
                   {:|, _,
                    [
                      {head, _, nil},
                      {tail, _, nil}
                    ]}
                 ]
               ]}
            ],
            body
          ]},
         var
       )
       when is_atom(head) and is_atom(tail) do
    match_slice_body?(body, var)
  end

  defp match_head_tail_clause?(_, _), do: false

  # Match: String.slice(var, 0, String.length(var) - 1)
  defp match_slice_body?(
         {{:., _, [{:__aliases__, _, [:String]}, :slice]}, _,
          [
            {var, _, nil},
            {:__block__, _, [0]},
            {:-, _,
             [
               {{:., _, [{:__aliases__, _, [:String]}, :length]}, _, [{var2, _, nil}]},
               {:__block__, _, [1]}
             ]}
          ]},
         var
       )
       when is_atom(var) and is_atom(var2) and var == var2 do
    true
  end

  defp match_slice_body?(_, _), do: false

  # Build: String.slice(var, 0..-2//1)
  defp build_replacement(var) do
    {:__block__, [],
     [
       {{:., [], [{:__aliases__, [], [:String]}, :slice]}, [],
        [
          {var, [], nil},
          {:..//, [],
           [
             {:__block__, [], [0]},
             {:-, [], [{:__block__, [], [2]}]},
             {:__block__, [], [1]}
           ]}
        ]}
     ]}
  end

  defp build_issue(node) do
    meta =
      case node do
        {_, m, _} when is_list(m) -> m
        _ -> []
      end

    %Issue{
      rule: :prefer_string_slice_for_trim_last_char,
      message:
        "Use `String.slice(str, 0..-2//1)` instead of a verbose `case` on " <>
          "`String.graphemes/1` to remove the last character.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
