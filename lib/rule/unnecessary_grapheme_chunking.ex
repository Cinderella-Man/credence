defmodule Credence.Rule.UnnecessaryGraphemeChunking do
  @moduledoc """
  Detects the common n-gram generation pipeline that converts a string
  to graphemes, creates sliding window chunks of step 1, and joins them
  back into strings. This pattern is automatically fixed by replacing it
  with `String.slice/3` which avoids intermediate list allocations.

  ## Bad

      string
      |> String.graphemes()
      |> Enum.chunk_every(n, 1, :discard)
      |> Enum.map(&Enum.join/1)

  ## Good

      for i <- 0..(String.length(string) - n) do
        String.slice(string, i, n)
      end

  `String.length/1` and `String.slice/3` both operate on grapheme clusters,
  so this replacement is semantically equivalent for the common case where
  the string length >= chunk size.
  """

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case detect_fixable_pipeline(node) do
          {:ok, _subject, _n} ->
            {node, [trigger_issue(node) | acc]}

          :error ->
            {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    source
    |> Code.string_to_quoted!()
    |> Macro.postwalk(fn node ->
      case detect_fixable_pipeline(node) do
        {:ok, subject, n} -> build_replacement(subject, n)
        :error -> node
      end
    end)
    |> Macro.to_string()
  end

  # ---------------------------------------------------------------------------
  # Pipeline detection
  # ---------------------------------------------------------------------------

  # Matches: subject |> String.graphemes() |> Enum.chunk_every(n, 1, ...) |> Enum.map(join_fn)
  defp detect_fixable_pipeline(
         {:|>, _,
          [
            {:|>, _,
             [
               {:|>, _, [subject, graphemes_call]},
               chunk_call
             ]},
            map_call
          ]}
       ) do
    if graphemes_call?(graphemes_call) &&
         chunk_every_sliding?(chunk_call) &&
         map_join?(map_call) do
      case extract_chunk_size(chunk_call) do
        nil -> :error
        n -> {:ok, subject, n}
      end
    else
      :error
    end
  end

  defp detect_fixable_pipeline(_), do: :error

  # ---------------------------------------------------------------------------
  # AST predicates
  # ---------------------------------------------------------------------------

  defp graphemes_call?({{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, _}), do: true
  defp graphemes_call?(_), do: false

  defp chunk_every_sliding?({{:., _, [{:__aliases__, _, [:Enum]}, :chunk_every]}, _, [_, 1]}),
    do: true

  defp chunk_every_sliding?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :chunk_every]}, _, [_, 1, :discard]}
       ),
       do: true

  defp chunk_every_sliding?(_), do: false

  defp extract_chunk_size({{:., _, _}, _, [n | _]}), do: n
  defp extract_chunk_size(_), do: nil

  defp map_join?({{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [join_fn]}),
    do: join_function?(join_fn)

  defp map_join?(_), do: false

  # Specific patterns — these match exact AST structures

  # &Enum.join/1
  defp join_function?(
         {:&, _, [{:/, _, [{{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, _}, 1]}]}
       ),
       do: true

  # &Enum.join(&1)
  defp join_function?({:&, _, [{{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, [{:&, _, 1}]}]}),
    do: true

  # &Enum.join(&1, "")
  defp join_function?(
         {:&, _, [{{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, [{:&, _, 1}, ""]}]}
       ),
       do: true

  # fn x -> Enum.join(x) end
  defp join_function?(
         {:fn, _, [{:->, _, [[_], {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, [_]}]}]}
       ),
       do: true

  # fn x -> Enum.join(x, "") end
  defp join_function?(
         {:fn, _, [{:->, _, [[_], {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, [_, ""]}]}]}
       ),
       do: true

  # Catch-all: handles any AST form whose string representation is a call to
  # Enum.join (e.g. parser-generated variants we didn't anticipate).
  # Safe because Enum.join is always a join — there's no false-positive path.
  defp join_function?(ast) do
    ast
    |> Macro.to_string()
    |> String.contains?("Enum.join")
  end

  # ---------------------------------------------------------------------------
  # Replacement builder
  # ---------------------------------------------------------------------------

  # Builds: for i <- 0..(String.length(subject) - n), do: String.slice(subject, i, n)
  defp build_replacement(subject, n) do
    length_call =
      {{:., [], [{:__aliases__, [], [:String]}, :length]}, [], [subject]}

    range =
      {:.., [], [0, {:-, [], [length_call, n]}]}

    body =
      {{:., [], [{:__aliases__, [], [:String]}, :slice]}, [], [subject, {:i, [], nil}, n]}

    {:for, [], [{:<-, [], [{:i, [], nil}, range]}, [do: body]]}
  end

  # ---------------------------------------------------------------------------
  # Issue
  # ---------------------------------------------------------------------------

  defp trigger_issue(node) do
    %Issue{
      rule: :unnecessary_grapheme_chunking,
      message: """
      This pipeline converts a string to graphemes, creates sliding window chunks,
      and joins them back into strings. This can be replaced with `String.slice/3`
      which avoids the intermediate list allocations:

          for i <- 0..(String.length(string) - n) do
            String.slice(string, i, n)
          end
      """,
      meta: %{line: get_line(node)}
    }
  end

  defp get_line({:|>, meta, _}), do: Keyword.get(meta, :line)
  defp get_line(_), do: nil
end
