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

      # In a pipeline
      string
      |> String.graphemes()
      |> length()

      # As a direct call
      length(String.graphemes(string))

  ## Good

      String.length(string)

      # Or in a pipeline:
      string
      |> String.length()
  """

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:|>, meta, [lhs, {:length, _, _}]} = node, issues ->
          if immediate_graphemes?(lhs) do
            {node, [trigger_issue(meta) | issues]}
          else
            {node, issues}
          end

        {:length, meta, [arg]} = node, issues ->
          if graphemes_call?(arg) do
            {node, [trigger_issue(meta) | issues]}
          else
            {node, issues}
          end

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
    |> Sourceror.to_string()
  end

  # String.graphemes(x) |> length() → String.length(x)
  defp fix_pipe_length(
         {{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, args},
         _node
       ) do
    subject = if args == [], do: raise("unreachable"), else: hd(args)
    string_length_call(subject)
  end

  # x |> String.graphemes() |> length() → x |> String.length()
  defp fix_pipe_length(
         {:|>, pipe_meta, [deeper, {{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, _}]},
         _node
       ) do
    {:|>, pipe_meta, [deeper, {{:., [], [{:__aliases__, [], [:String]}, :length]}, [], []}]}
  end

  defp fix_pipe_length(_, node), do: node

  defp extract_graphemes_arg({{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, [subject]}),
    do: {:ok, subject}

  defp extract_graphemes_arg(_), do: :error

  defp string_length_call(subject) do
    {{:., [], [{:__aliases__, [], [:String]}, :length]}, [], [subject]}
  end

  defp immediate_graphemes?({:|>, _, [_, rhs]}), do: graphemes_call?(rhs)
  defp immediate_graphemes?(other), do: graphemes_call?(other)

  defp graphemes_call?({{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, args})
       when is_list(args),
       do: true

  defp graphemes_call?(_), do: false

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
