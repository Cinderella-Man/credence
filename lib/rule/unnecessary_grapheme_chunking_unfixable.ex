defmodule Credence.Rule.UnnecessaryGraphemeChunking.Unfixable do
  @moduledoc """
  Detects inefficient string transformation pipelines that convert strings
  to graphemes or codepoints, perform chunking or grouping, and reconstruct
  strings from the result. These patterns cannot be automatically fixed.

  This rule catches variants NOT covered by the fixable
  `UnnecessaryGraphemeChunking` rule, including:

  - Using `String.codepoints/1` instead of `String.graphemes/1`
    (`String.slice/3` operates on graphemes, not codepoints)
  - Using `Enum.chunk_by/2` (predicate-based grouping, not a sliding window)
  - Using `Enum.split/2` (splits at an index, not a chunking operation)
  - Using `Enum.chunk_every` with step != 1 (non-standard window stride)
  - Using `Enum.chunk_every` with `:trim` leftover (includes incomplete
    trailing chunks, which `String.slice`-based replacement would drop)
  - Using a map function other than `Enum.join/1`

  ## Why this is a problem

  Elixir strings are UTF-8 binaries. Converting them into grapheme lists:

      String.graphemes("café")
      # => ["c", "a", "f", "é"]

  creates a full intermediate structure in memory. If we then chunk and
  rebuild strings, we are effectively doing:

      binary → list → list of lists → binaries

  which increases memory usage, CPU cost, and GC pressure.

  ## Recommended alternatives

  1. Direct binary slicing (when possible):

        for i <- 0..(String.length(string) - n) do
          String.slice(string, i, n)
        end

  2. Single grapheme conversion (if Unicode safety is required):

        graphemes = String.graphemes(string)
        for i <- 0..(length(graphemes) - n) do
          graphemes |> Enum.slice(i, n) |> Enum.join()
        end

  3. Algorithmic restructuring — in many cases substring generation
     is not needed at all and can be replaced with streaming or
     incremental computation.
  """

  use Credence.Rule
  alias Credence.Issue

  @string_to_list [:graphemes, :codepoints]
  @chunk [:chunk_every, :chunk_by, :split]
  @map [:map]

  @impl true
  def fixable?, do: false

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case detect_pipeline(node) do
          nil -> {node, acc}
          issue -> {node, [issue | acc]}
        end
      end)

    Enum.reverse(issues)
  end

  # ---------------------------------------------------------------------------
  # Pipeline detection
  # ---------------------------------------------------------------------------

  defp detect_pipeline({:|>, meta, _} = node) do
    calls = flatten_pipeline(node)

    if broad_pattern?(calls) && !fixable_pattern?(calls) do
      %Issue{
        rule: :unnecessary_grapheme_chunking,
        message: message(),
        meta: %{line: Keyword.get(meta, :line)}
      }
    else
      nil
    end
  end

  defp detect_pipeline(_), do: nil

  # ---------------------------------------------------------------------------
  # Flatten pipeline into ordered list of calls
  # ---------------------------------------------------------------------------

  defp flatten_pipeline({:|>, _, [left, right]}) do
    flatten_pipeline(left) ++ [right]
  end

  defp flatten_pipeline(expr), do: [expr]

  # ---------------------------------------------------------------------------
  # Broad pattern detection (same as original rule)
  # ---------------------------------------------------------------------------

  defp broad_pattern?(calls) do
    has_graphemes_or_codepoints? =
      Enum.any?(
        calls,
        &match?(
          {{:., _, [{:__aliases__, _, [:String]}, f]}, _, _}
          when f in @string_to_list,
          &1
        )
      )

    has_chunk? =
      Enum.any?(
        calls,
        &match?(
          {{:., _, [{:__aliases__, _, [:Enum]}, f]}, _, _}
          when f in @chunk,
          &1
        )
      )

    has_map? =
      Enum.any?(
        calls,
        &match?(
          {{:., _, [{:__aliases__, _, [:Enum]}, f]}, _, _}
          when f in @map,
          &1
        )
      )

    has_graphemes_or_codepoints? and has_chunk? and has_map?
  end

  # ---------------------------------------------------------------------------
  # Narrow fixable-pattern exclusion
  # ---------------------------------------------------------------------------

  # Returns true if the pipeline matches the fixable pattern:
  #   String.graphemes() |> Enum.chunk_every(_, 1|1,:discard) |> Enum.map(join_fn)
  # in that order. These should be flagged by the fixable module instead.
  defp fixable_pattern?(calls) do
    graphemes_idx = Enum.find_index(calls, &graphemes_only_call?/1)
    chunk_idx = Enum.find_index(calls, &sliding_chunk_call?/1)
    map_idx = Enum.find_index(calls, &map_join_call?/1)

    case {graphemes_idx, chunk_idx, map_idx} do
      {g, c, m}
      when is_integer(g) and is_integer(c) and is_integer(m) and g < c and c < m ->
        true

      _ ->
        false
    end
  end

  defp graphemes_only_call?({{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, _}),
    do: true

  defp graphemes_only_call?(_), do: false

  defp sliding_chunk_call?({{:., _, [{:__aliases__, _, [:Enum]}, :chunk_every]}, _, [_, 1]}),
    do: true

  defp sliding_chunk_call?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :chunk_every]}, _, [_, 1, :discard]}
       ),
       do: true

  defp sliding_chunk_call?(_), do: false

  defp map_join_call?({{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [join_fn]}),
    do: join_function?(join_fn)

  defp map_join_call?(_), do: false

  defp join_function?(
         {:&, _, [{:/, _, [{{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, _}, 1]}]}
       ),
       do: true

  defp join_function?({:&, _, [{{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, [{:&, _, 1}]}]}),
    do: true

  defp join_function?(
         {:&, _, [{{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, [{:&, _, 1}, ""]}]}
       ),
       do: true

  defp join_function?(
         {:fn, _, [{:->, _, [[_], {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, [_]}]}]}
       ),
       do: true

  defp join_function?(
         {:fn, _, [{:->, _, [[_], {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, [_, ""]}]}]}
       ),
       do: true

  defp join_function?(_), do: false

  # ---------------------------------------------------------------------------
  # Message
  # ---------------------------------------------------------------------------

  defp message do
    """
    This code converts a string into graphemes or codepoints, chunks the result,
    and then rebuilds strings from each chunk.
    This creates a full allocation chain:
      String (binary)
        → List of graphemes
        → List of chunks (nested lists)
        → Reconstructed binaries via Enum.map + Enum.join
    This is usually unnecessary and can often be simplified.
    Alternatives:
    1. Direct binary slicing (preferred when possible):
        for i <- 0..(String.length(string) - n) do
          String.slice(string, i, n)
        end
    2. If Unicode safety is required:
        graphemes = String.graphemes(string)
        for i <- 0..(length(graphemes) - n) do
          graphemes |> Enum.slice(i, n) |> Enum.join()
        end
    3. Or redesign the algorithm to avoid rebuilding substrings entirely.
    """
  end
end
