defmodule Credence.Pattern.NoManualStringReverse do
  @moduledoc """
  Readability & performance rule: Detects the pattern
  `String.graphemes(s) |> Enum.reverse() |> Enum.join()` (and the nested
  equivalent `Enum.join(Enum.reverse(String.graphemes(s)))`) which is a manual
  reimplementation of `String.reverse/1`.

  `String.reverse/1` handles Unicode grapheme clusters correctly and avoids
  creating an intermediate list, making it both clearer and faster.

  ## Bad

      # In a pipeline
      reversed = str |> String.graphemes() |> Enum.reverse() |> Enum.join()

      # As a nested call
      reversed = Enum.join(Enum.reverse(String.graphemes(str)))

  ## Good

      reversed = String.reverse(str)
  """
  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipeline form: ... |> String.graphemes() |> Enum.reverse() |> Enum.join()
        #
        # `a |> b() |> c()` parses as {:|>, _, [{:|>, _, [a, b]}, c]}.
        # So the outer pipe has `c` on the right and the inner chain on the left.
        # We check: right == Enum.join, predecessor == Enum.reverse, predecessor's predecessor == String.graphemes.
        {:|>, meta, [left, right]} = node, issues ->
          if remote_call?(right, :Enum, :join) and remote_call?(rightmost(left), :Enum, :reverse) do
            grandparent =
              case left do
                {:|>, _, [inner_left, _]} -> rightmost(inner_left)
                _ -> nil
              end

            if grandparent != nil and remote_call?(grandparent, :String, :graphemes) do
              {node, [build_issue(meta) | issues]}
            else
              {node, issues}
            end
          else
            {node, issues}
          end

        # Nested call form: Enum.join(Enum.reverse(String.graphemes(s)))
        {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, meta,
         [
           {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _,
            [
              {{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, _}
            ]}
         ]} = node,
        issues ->
          {node, [build_issue(meta) | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      # Pipeline: ... |> String.graphemes() |> Enum.reverse() |> Enum.join()
      #
      # Matches the outermost `|>` whose right side is Enum.join(),
      # then verifies the two preceding pipe stages are Enum.reverse()
      # and String.graphemes().  Only fires when Enum.join has no
      # explicit separator (safe replacement).
      {:|>, _, [left, join]} = node ->
        if remote_call?(join, :Enum, :join) and join_no_separator?(join) do
          case left do
            {:|>, _, [middle, reverse]} ->
              if remote_call?(reverse, :Enum, :reverse) do
                case graphemes_in_middle(middle) do
                  {:ok, subject} -> fix_pipe_subject(subject)
                  :error -> node
                end
              else
                node
              end

            _ ->
              node
          end
        else
          node
        end

      # Nested: Enum.join(Enum.reverse(String.graphemes(s)))
      {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, [single_arg]} = node ->
        case single_arg do
          {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _,
           [{{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, [subject]}]} ->
            string_reverse_call(subject)

          _ ->
            node
        end

      node ->
        node
    end)
    |> Sourceror.to_string()
  end

  # Extracts the subject from String.graphemes in the middle of a pipe chain.
  # Handles both `subject |> String.graphemes()` and `String.graphemes(subject)`.
  defp graphemes_in_middle({:|>, _, [subject, graphemes]}) do
    if remote_call?(graphemes, :String, :graphemes), do: {:ok, subject}, else: :error
  end

  defp graphemes_in_middle({{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, [subject]}) do
    {:ok, subject}
  end

  defp graphemes_in_middle(_), do: :error

  # When the subject is already a pipeline, append String.reverse() at the end.
  # Otherwise wrap in a direct call: String.reverse(subject).
  defp fix_pipe_subject({:|>, _, _} = pipe) do
    {:|>, [], [pipe, string_reverse_call()]}
  end

  defp fix_pipe_subject(subject) do
    string_reverse_call(subject)
  end

  # AST for `String.reverse()` (no args – value arrives via pipe)
  defp string_reverse_call do
    {{:., [], [{:__aliases__, [], [:String]}, :reverse]}, [], []}
  end

  # AST for `String.reverse(subject)`
  defp string_reverse_call(subject) do
    {{:., [], [{:__aliases__, [], [:String]}, :reverse]}, [], [subject]}
  end

  # Safe to auto-fix when Enum.join has no separator or an empty-string
  # separator (which is the default). A non-empty separator would change
  # semantics (e.g. Enum.join(list, "-") ≠ String.reverse).
  defp join_no_separator?({{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, []}), do: true

  defp join_no_separator?({{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, [sep]}),
    do: empty_string_literal?(sep)

  defp join_no_separator?(_), do: false

  defp empty_string_literal?(""), do: true
  defp empty_string_literal?({:__block__, _, [""]}), do: true
  defp empty_string_literal?(_), do: false

  defp rightmost({:|>, _, [_, right]}), do: right
  defp rightmost(other), do: other

  defp remote_call?(node, mod, func) do
    match?({{:., _, [{:__aliases__, _, [^mod]}, ^func]}, _, _}, node)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_manual_string_reverse,
      message:
        "Use `String.reverse/1` instead of `String.graphemes/1 |> Enum.reverse/0 |> Enum.join/0`. " <>
          "It is clearer and avoids creating an intermediate list.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
