defmodule Credence.Pattern.AvoidGraphemesEnumCountWithPredicate do
  @moduledoc """
  Performance rule: Detects `Enum.count/2` with an equality predicate or
  `Enum.sum_by/2` with a counting function on the result of `String.graphemes/1`.

  Splitting a string into a grapheme list just to count occurrences of a
  specific character is wasteful. `String.count/2` performs the same count
  directly on the string without allocating the intermediate list.

  ## Safety: behind a switch

  The rewrite is identical to the original only while every character in the
  *running data* is a single codepoint — otherwise `String.count/2` (which scans
  raw text) and the grapheme comparison disagree on a decomposed accent. So this
  rule needs `single_codepoint_graphemes` (see `Credence.Assumptions`) and runs
  only while that promise is on.

  Two guards keep the rewrite honest (decision 6a — shrink first, then promise):

  1. The compared literal is narrowed to a **single codepoint**
     (`length(String.to_charlist(lit)) == 1`), dropping `""`, `"ab"`, and the
     two-codepoint form of `"é"`. After that narrowing the only remaining
     difference between old and new is the rare decomposed-accent case in the
     *data* — which is exactly what the promise covers.
  2. A shared `single_codepoint?/1` helper gates both `check` and `fix`, so they
     can never disagree on which literals qualify.

  ## Bad

      String.graphemes(str) |> Enum.count(&(&1 == "1"))
      Enum.count(String.graphemes(str), &(&1 == "1"))
      str |> String.graphemes() |> Enum.count(fn c -> c == "1" end)

      String.graphemes(str) |> Enum.sum_by(fn "1" -> 1; _ -> 0 end)
      Enum.sum_by(String.graphemes(str), fn "1" -> 1; _ -> 0 end)

  ## Good

      String.count(str, "1")
      str |> String.count("1")
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def assumptions, do: [:single_codepoint_graphemes]

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipe form: ... |> Enum.count(predicate)
        {:|>, meta, [lhs, rhs]} = node, issues ->
          with {:ok, _literal} <- extract_enum_count_pred_literal(rhs),
               true <- immediate_graphemes?(lhs) do
            {node, [build_issue(meta) | issues]}
          else
            _ ->
              # Pipe form: ... |> Enum.sum_by(fn literal -> 1; _ -> 0 end)
              with {:ok, _literal} <- extract_sum_by_counting_literal(rhs),
                   true <- immediate_graphemes?(lhs) do
                {node, [build_issue(meta) | issues]}
              else
                _ -> {node, issues}
              end
          end

        # Direct: Enum.count(String.graphemes(...), predicate)
        {{:., meta, [{:__aliases__, _, [:Enum]}, :count]}, _, [arg, pred]} = node, issues ->
          with {:ok, _literal} <- equality_literal(pred),
               true <- graphemes_call?(arg) do
            {node, [build_issue(meta) | issues]}
          else
            _ -> {node, issues}
          end

        # Direct: Enum.sum_by(String.graphemes(...), fn literal -> 1; _ -> 0 end)
        {{:., meta, [{:__aliases__, _, [:Enum]}, :sum_by]}, _, [arg, fn_ast]} = node, issues ->
          with {:ok, _literal} <- sum_by_counting_literal(fn_ast),
               true <- graphemes_call?(arg) do
            {node, [build_issue(meta) | issues]}
          else
            _ -> {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      # Pipe: ... |> String.graphemes() |> Enum.count(pred)
      {:|>, _, [lhs, rhs]} = node ->
        with {:ok, literal} <- extract_enum_count_pred_literal(rhs),
             true <- immediate_graphemes?(lhs) do
          fix_pipe(lhs, literal)
        else
          _ ->
            # Pipe: ... |> String.graphemes() |> Enum.sum_by(fn literal -> 1; _ -> 0 end)
            with {:ok, literal} <- extract_sum_by_counting_literal(rhs),
                 true <- immediate_graphemes?(lhs) do
              fix_pipe(lhs, literal)
            else
              _ -> node
            end
        end

      # Direct: Enum.count(String.graphemes(x), pred)
      {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, [arg, pred]} = node ->
        with {:ok, literal} <- equality_literal(pred),
             {:ok, subject} <- extract_graphemes_arg(arg) do
          string_count_call(subject, literal)
        else
          _ -> node
        end

      # Direct: Enum.sum_by(String.graphemes(x), fn literal -> 1; _ -> 0 end)
      {{:., _, [{:__aliases__, _, [:Enum]}, :sum_by]}, _, [arg, fn_ast]} = node ->
        with {:ok, literal} <- sum_by_counting_literal(fn_ast),
             {:ok, subject} <- extract_graphemes_arg(arg) do
          string_count_call(subject, literal)
        else
          _ -> node
        end

      node ->
        node
    end)
  end

  # String.graphemes(x) |> Enum.count(pred) → String.count(x, literal)
  defp fix_pipe(
         {{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, [subject]},
         literal
       ) do
    string_count_call(subject, literal)
  end

  # x |> String.graphemes() |> Enum.count(pred)
  # → String.count(x, literal) when x is a simple expression
  # → x |> String.count(literal) when x is an upstream pipeline
  defp fix_pipe(
         {:|>, pipe_meta, [deeper, {{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, _}]},
         literal
       ) do
    case deeper do
      {:|>, _, _} ->
        {:|>, pipe_meta,
         [deeper, {{:., [], [{:__aliases__, [], [:String]}, :count]}, [], [literal]}]}

      _ ->
        string_count_call(deeper, literal)
    end
  end

  defp fix_pipe(lhs, _literal), do: lhs

  defp string_count_call(subject, literal) do
    {{:., [], [{:__aliases__, [], [:String]}, :count]}, [], [subject, literal]}
  end

  # Extract literal from Enum.count/2 in a pipe (only pred arg present)
  defp extract_enum_count_pred_literal({{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, [pred]}) do
    equality_literal(pred)
  end

  defp extract_enum_count_pred_literal(_), do: :error

  # Extract literal from Enum.sum_by/2 in a pipe (only fn arg present)
  defp extract_sum_by_counting_literal(
         {{:., _, [{:__aliases__, _, [:Enum]}, :sum_by]}, _, [fn_ast]}
       ) do
    sum_by_counting_literal(fn_ast)
  end

  defp extract_sum_by_counting_literal(_), do: :error

  # Match fn literal -> 1; _ -> 0 end (two-clause counting function)
  defp sum_by_counting_literal(
         {:fn, _,
          [
            {:->, _, [[{:__block__, _, [literal]}], {:__block__, _, [1]}]},
            {:->, _, [[{:_, _, _}], {:__block__, _, [0]}]}
          ]}
       )
       when is_binary(literal),
       do: ok_if_single_codepoint(literal)

  # Same but with variable instead of underscore in catch-all
  defp sum_by_counting_literal(
         {:fn, _,
          [
            {:->, _, [[{:__block__, _, [literal]}], {:__block__, _, [1]}]},
            {:->, _, [[{_var, _, _}], {:__block__, _, [0]}]}
          ]}
       )
       when is_binary(literal),
       do: ok_if_single_codepoint(literal)

  defp sum_by_counting_literal(_), do: :error

  # Match &(&1 == literal) or &(&1 === literal)
  defp equality_literal({:&, _, [{op, _, [{:&, _, [1]}, {:__block__, _, [literal]}]}]})
       when op in [:==, :===] and is_binary(literal),
       do: ok_if_single_codepoint(literal)

  # Match fn c -> c == literal end or fn c -> c === literal end
  defp equality_literal(
         {:fn, _,
          [
            {:->, _,
             [
               [{var, _, _}],
               {op, _, [{var, _, _}, {:__block__, _, [literal]}]}
             ]}
          ]}
       )
       when op in [:==, :===] and is_binary(literal) and is_atom(var),
       do: ok_if_single_codepoint(literal)

  defp equality_literal(_), do: :error

  # The shrink-first narrowing (decision 6a), shared by check and fix so they
  # never disagree: only single-codepoint literals qualify, leaving the promise
  # to cover only the rare-data difference. Drops "", "ab", and the two-codepoint
  # form of "é"; keeps "a", " ", and the precomposed one-codepoint "é".
  defp ok_if_single_codepoint(literal) do
    if single_codepoint?(literal), do: {:ok, literal}, else: :error
  end

  defp single_codepoint?(literal) when is_binary(literal) do
    length(String.to_charlist(literal)) == 1
  end

  defp extract_graphemes_arg({{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, [subject]}),
    do: {:ok, subject}

  defp extract_graphemes_arg(_), do: :error

  defp immediate_graphemes?({:|>, _, [_, rhs]}), do: graphemes_call?(rhs)
  defp immediate_graphemes?(other), do: graphemes_call?(other)

  defp graphemes_call?({{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, args})
       when is_list(args),
       do: true

  defp graphemes_call?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :avoid_graphemes_enum_count_with_predicate,
      message: """
      `String.graphemes/1` allocates an intermediate list of every grapheme \
      just to count occurrences of a specific character. `String.count/2` \
      performs the same count directly on the string without the allocation.

      Replace the pattern with `String.count/2`:

          # Before (allocates a list):
          String.graphemes(str) |> Enum.count(&(&1 == "1"))
          Enum.count(String.graphemes(str), &(&1 == "1"))

          # After (no intermediate list):
          String.count(str, "1")
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
