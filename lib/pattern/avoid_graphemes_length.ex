defmodule Credence.Pattern.AvoidGraphemesLength do
  @moduledoc """
  Performance rule: Detects the use of `length/1` on the result of
  `String.graphemes/1`.

  Calling `String.graphemes/1` eagerly allocates a list containing every
  grapheme in the string. If your only goal is to find out how many characters
  there are, this list is immediately garbage collected after `length/1` finishes.

  Using `String.length/1` calculates the character count directly without
  building this intermediate list, making it significantly more memory efficient.

  ## Bad

      defmodule CounterAGL do
        def size(string), do: string |> String.graphemes() |> length()
        def direct(string), do: length(String.graphemes(string))
      end

  ## Good

      defmodule CounterAGL do
        def size(string), do: String.length(string)
        def direct(string), do: String.length(string)
      end
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
          {:|>, meta, [lhs, {:length, _, _}]} = node, issues ->
            if immediate_graphemes?(lhs) do
              {node, [trigger_issue(meta) | issues]}
            else
              {node, issues}
            end

          {:length, meta, [arg]} = node, issues ->
            if direct_graphemes_call?(arg) do
              {node, [trigger_issue(meta) | issues]}
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
      # Pipe: String.graphemes(x) |> length()
      {:|>, _, [lhs, {:length, _, _}]} = node ->
        fix_pipe_length(lhs, node)

      # Direct: length(String.graphemes(x))
      {:length, _, [arg]} = node ->
        case extract_graphemes_arg(arg) do
          {:ok, subject} -> string_length_call(subject)
          :error -> node
        end

      node ->
        node
    end)
  end

  # String.graphemes(x) |> length() → String.length(x)
  defp fix_pipe_length(
         {{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, [subject]},
         _node
       ) do
    string_length_call(subject)
  end

  # x |> String.graphemes() |> length()
  # → String.length(x) when x is a simple expression
  # → x |> String.length() when x is an upstream pipeline
  defp fix_pipe_length(
         {:|>, pipe_meta, [deeper, {{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, []}]},
         _node
       ) do
    case deeper do
      {:|>, _, _} ->
        {:|>, pipe_meta, [deeper, {{:., [], [{:__aliases__, [], [:String]}, :length]}, [], []}]}

      _ ->
        string_length_call(deeper)
    end
  end

  defp fix_pipe_length(_, node), do: node

  defp extract_graphemes_arg({{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, [subject]}),
    do: {:ok, subject}

  defp extract_graphemes_arg(_), do: :error

  defp string_length_call(subject) do
    {{:., [], [{:__aliases__, [], [:String]}, :length]}, [], [subject]}
  end

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

  defp trigger_issue(meta) do
    %Issue{
      rule: :avoid_graphemes_length,
      message: """
      Use `String.length/1` instead of counting `String.graphemes/1`.

      `String.graphemes/1` builds an intermediate list that is immediately
      discarded, while `String.length/1` avoids this allocation.
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
