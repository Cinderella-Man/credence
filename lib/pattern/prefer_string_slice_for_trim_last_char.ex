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

  # Match a `case` whose clauses all agree on "give me everything but the last
  # character", regardless of which shapes the author enumerated.
  #
  # ## Why this is not the three fixed clauses it used to be
  #
  # The matcher was positional: exactly three clauses, `[] -> ""` first,
  # `[_last] -> ""` second, cons-to-slice third, and `String.graphemes` as the
  # subject. docs/12 C12(c) called this rule over-fit in SHAPE, and probing it
  # agreed — these all express the identical function and none of them fired:
  #
  #     case String.graphemes(s) do          case String.codepoints(s) do
  #       [] -> ""                             [] -> ""
  #       _ -> String.slice(...)               [_last] -> ""
  #     end                                    [_h | _t] -> String.slice(...)
  #                                          end
  #
  # Equivalence to `String.slice(str, 0..-2//1)` was EXECUTED for each variant
  # over combining characters, ZWJ emoji and CJK, not argued from the shapes.
  # The 2-clause form differs from the 3-clause form only on a single-grapheme
  # string, where both return `""`. `String.codepoints` differs from
  # `String.graphemes` only on multi-codepoint graphemes, where it takes the
  # cons branch and `String.length/1` — still grapheme-based — makes the slice
  # `""` anyway.
  #
  # ## The boundary, and why it is here
  #
  # Accepted: any clause set where exactly one clause slices, it comes LAST, and
  # every earlier clause returns `""` for a shape that is empty or single.
  #
  # Not accepted: the slice clause appearing FIRST. It is equivalent — that was
  # measured too — but a leading `[_h | _t]` makes the trailing `[_last]` and
  # `[]` clauses unreachable, and unreachable clauses are a different defect with
  # a different rule (`RemoveUnreachableClausesAfterCatchall`). Rewriting the
  # whole `case` away would silently take that finding with it.
  defp match_trim_last_char({:case, _meta, [subject, clauses_kw]}) do
    with {:ok, var} <- match_grapheme_list_subject(subject),
         {:ok, clauses} <- extract_do_clauses(clauses_kw),
         true <- length(clauses) >= 2,
         {leading, [last]} <- Enum.split(clauses, -1),
         true <- match_slice_clause?(last, var),
         true <- Enum.all?(leading, &match_empty_result_clause?/1) do
      {:ok, var}
    else
      _ -> :error
    end
  end

  defp match_trim_last_char(_), do: :error

  # Match: `String.graphemes(var)` or `String.codepoints(var)`. Both only ever
  # feed the emptiness/length test above; the slice itself uses
  # `String.length/1`, which is grapheme-based either way.
  defp match_grapheme_list_subject(
         {{:., _, [{:__aliases__, _, [:String]}, fun]}, _, [{var, _, nil}]}
       )
       when fun in [:graphemes, :codepoints] and is_atom(var) do
    {:ok, var}
  end

  defp match_grapheme_list_subject(_), do: :error

  # A clause that returns `""` for a shape holding at most one element: `[]` or
  # `[_x]`. Deliberately NOT a bare `_` — a leading `_ -> ""` would send every
  # input to `""`, which is a different function entirely, not this idiom.
  defp match_empty_result_clause?(clause) do
    match_empty_clause?(clause) or match_single_clause?(clause)
  end

  # The clause that does the slicing, under either `[_h | _t]` or a bare
  # wildcard. A wildcard here is what makes the two-clause form work.
  defp match_slice_clause?(clause, var) do
    match_head_tail_clause?(clause, var) or match_wildcard_slice_clause?(clause, var)
  end

  defp match_wildcard_slice_clause?({:->, _, [[{var_name, _, nil}], body]}, var)
       when is_atom(var_name) do
    match_slice_body?(body, var)
  end

  defp match_wildcard_slice_clause?(_, _), do: false

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
