defmodule Credence.Pattern.AvoidGraphemesEnumCount do
  @moduledoc """
  Performance rule: Detects `Enum.count/1` on the result of
  `String.graphemes/1` (without a predicate).

  Calling `String.graphemes/1` eagerly allocates a list of every grapheme
  in the string. If the goal is simply to count characters,
  `String.length/1` accomplishes this without the intermediate list.

  Note: the predicate variant (`Enum.count/2` with a filter function) is
  handled by the separate `AvoidGraphemesEnumCountWithPredicate` rule,
  which flags but does not auto-fix because the lazy-stream replacement
  can produce different results under Unicode normalization changes.

  ## Bad

      string |> String.graphemes() |> Enum.count()
      Enum.count(String.graphemes(string))

  ## Good

      String.length(string)

      # Or in a pipeline:
      string |> String.length()
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    if string_alias_shadowed?(ast) do
      []
    else
      {_ast, issues} =
        Macro.prewalk(ast, [], fn
          # Pipe form: ... |> Enum.count()
          {:|>, meta, [lhs, rhs]} = node, issues ->
            if enum_count_no_pred?(rhs) and immediate_graphemes?(lhs) do
              {node, [build_issue(meta) | issues]}
            else
              {node, issues}
            end

          # Direct: Enum.count(String.graphemes(...))
          {{:., meta, [{:__aliases__, _, [:Enum]}, :count]}, _, [arg]} = node, issues ->
            if direct_graphemes_call?(arg) do
              {node, [build_issue(meta) | issues]}
            else
              {node, issues}
            end

          node, issues ->
            {node, issues}
        end)

      Enum.reverse(issues)
    end
  end

  @impl true
  def fix_patches(ast, _opts) do
    if string_alias_shadowed?(ast), do: [], else: fix_unshadowed(ast)
  end

  defp fix_unshadowed(ast) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      # Pipe: ... |> String.graphemes() |> Enum.count()
      {:|>, _, [lhs, rhs]} = node when is_tuple(rhs) ->
        if enum_count_no_pred?(rhs) and immediate_graphemes?(lhs) do
          fix_pipe(lhs)
        else
          node
        end

      # Direct: Enum.count(String.graphemes(x))
      {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, [arg]} = node ->
        case extract_graphemes_arg(arg) do
          {:ok, subject} -> string_length_call(subject)
          :error -> node
        end

      node ->
        node
    end)
  end

  # String.graphemes(x) |> Enum.count() → String.length(x)
  defp fix_pipe({{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, [subject]}) do
    string_length_call(subject)
  end

  # x |> String.graphemes() |> Enum.count()
  defp fix_pipe(
         {:|>, pipe_meta, [deeper, {{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, []}]}
       ) do
    case deeper do
      {:|>, _, _} ->
        {:|>, pipe_meta, [deeper, {{:., [], [{:__aliases__, [], [:String]}, :length]}, [], []}]}

      _ ->
        string_length_call(deeper)
    end
  end

  defp fix_pipe(lhs), do: lhs

  defp string_length_call(subject) do
    {{:., [], [{:__aliases__, [], [:String]}, :length]}, [], [subject]}
  end

  defp extract_graphemes_arg({{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, [subject]}),
    do: {:ok, subject}

  defp extract_graphemes_arg(_), do: :error

  defp enum_count_no_pred?({{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, []}), do: true
  defp enum_count_no_pred?(_), do: false

  defp immediate_graphemes?({:|>, _, [_, rhs]}), do: piped_graphemes_call?(rhs)
  defp immediate_graphemes?(other), do: direct_graphemes_call?(other)

  defp direct_graphemes_call?(
         {{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, [_subject]}
       ),
       do: true

  defp direct_graphemes_call?(_), do: false

  defp piped_graphemes_call?({{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, []}),
    do: true

  defp piped_graphemes_call?(_), do: false

  defp string_alias_shadowed?(ast) do
    {_ast, shadowed?} =
      Macro.prewalk(ast, false, fn
        {:alias, _, [{:__aliases__, _, target}, opts]} = node, shadowed?
        when is_list(target) and is_list(opts) ->
          {node, shadowed? or shadows_string?(target, alias_as(opts))}

        {:alias, _, [{:__aliases__, _, target}]} = node, shadowed? when is_list(target) ->
          {node, shadowed? or shadows_string?(target, nil)}

        node, shadowed? ->
          {node, shadowed?}
      end)

    shadowed?
  end

  defp alias_as(opts) do
    Enum.find_value(opts, fn
      {:as, value} -> value
      {{:__block__, _, [:as]}, value} -> value
      _other -> nil
    end)
  end

  defp shadows_string?(target, {:__aliases__, _, [:String]}), do: target != [:String]
  defp shadows_string?(target, nil), do: List.last(target) == :String and target != [:String]
  defp shadows_string?(_target, _as), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :avoid_graphemes_enum_count,
      message: """
      `String.graphemes/1 |> Enum.count()` allocates an intermediate list of \
      every grapheme in the string just to count them. `String.length/1` does \
      the same count in O(n) time without allocating the list.

      Replace the pattern with `String.length/1`:

          # Before (allocates a list):
          String.graphemes(str) |> Enum.count()
          Enum.count(String.graphemes(str))
          str |> String.graphemes() |> Enum.count()

          # After (no intermediate list):
          String.length(str)

          # In a pipeline, replace the last two steps:
          str |> String.trim() |> String.graphemes() |> Enum.count()
          # becomes:
          str |> String.trim() |> String.length()
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
