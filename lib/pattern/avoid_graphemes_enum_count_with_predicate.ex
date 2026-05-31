defmodule Credence.Pattern.AvoidGraphemesEnumCountWithPredicate do
  @moduledoc """
  Performance rule: Detects `Enum.count/2` with an equality predicate on the
  result of `String.graphemes/1`.

  Splitting a string into a grapheme list just to count occurrences of a
  specific character is wasteful. `String.count/2` performs the same count
  directly on the string without allocating the intermediate list.

  ## Bad

      String.graphemes(str) |> Enum.count(&(&1 == "1"))
      Enum.count(String.graphemes(str), &(&1 == "1"))
      str |> String.graphemes() |> Enum.count(fn c -> c == "1" end)

  ## Good

      String.count(str, "1")
      str |> String.count("1")
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

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
            _ -> {node, issues}
          end

        # Direct: Enum.count(String.graphemes(...), predicate)
        {{:., meta, [{:__aliases__, _, [:Enum]}, :count]}, _, [arg, pred]} = node, issues ->
          with {:ok, _literal} <- equality_literal(pred),
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
          _ -> node
        end

      # Direct: Enum.count(String.graphemes(x), pred)
      {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, [arg, pred]} = node ->
        with {:ok, literal} <- equality_literal(pred),
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
  defp extract_enum_count_pred_literal(
         {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, [pred]}
       ) do
    equality_literal(pred)
  end

  defp extract_enum_count_pred_literal(_), do: :error

  # Match &(&1 == literal) or &(&1 === literal)
  defp equality_literal({:&, _, [{op, _, [{:&, _, [1]}, {:__block__, _, [literal]}]}]})
       when op in [:==, :===] and is_binary(literal),
       do: {:ok, literal}

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
       do: {:ok, literal}

  defp equality_literal(_), do: :error

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
