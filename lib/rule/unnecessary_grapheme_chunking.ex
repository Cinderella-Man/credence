defmodule Credence.Rule.UnnecessaryGraphemeChunking do
  @moduledoc """
  Detects inefficient string transformation pipelines that:

  1. Convert a UTF-8 binary into graphemes or codepoints
  2. Perform chunking or grouping operations on the resulting list
  3. Immediately reconstruct strings from those chunks

  This pattern often indicates unnecessary intermediate allocations:
  binary → list → list of lists → binary

  While correct, this transformation is usually avoidable and can often
  be replaced with a more direct sliding-window or binary-based approach.

  ## Why this is a problem

  Elixir strings are UTF-8 binaries. Converting them into grapheme lists:

      String.graphemes("café")
      # => ["c", "a", "f", "é"]

  creates a full intermediate structure in memory. If we then chunk and
  rebuild strings, we are effectively doing:

      binary → list → list of lists → binaries

  which increases:
  - memory usage (multiple allocations)
  - CPU cost (repeated traversal)
  - garbage collection pressure

  ## Example (flagged)

      string
      |> String.graphemes()
      |> Enum.chunk_every(3, 1, :discard)
      |> Enum.map(&Enum.join/1)

  This:
  - expands the entire string into a list
  - builds overlapping sublists
  - reconstructs each substring separately

  ## Better alternatives

  ### 1. Direct binary slicing (preferred when valid)

      for i <- 0..String.length(string) - n do
        String.slice(string, i, n)
      end

  ### 2. Single grapheme conversion (if Unicode safety is required)

      graphemes = String.graphemes(string)

      for i <- 0..(length(graphemes) - n) do
        graphemes
        |> Enum.slice(i, n)
        |> Enum.join()
      end

  ### 3. Algorithmic restructuring

  In many cases, substring generation is not needed at all and can be
  replaced with a streaming or incremental computation.

  ## When NOT to flag

  - Small input sizes where clarity is more important than performance
  - One-off transformations in scripts or tests
  - Cases where grapheme correctness is explicitly required and simplicity is preferred
  """

  @behaviour Credence.Rule
  alias Credence.Issue

  @string_to_list [:graphemes, :codepoints]
  @chunk [:chunk_every, :chunk_by, :split]
  @map [:map]

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

  # STEP 1: detect full pipelines
  defp detect_pipeline({:|>, meta, _} = node) do
    calls = flatten_pipeline(node)

    if grapheme_chunk_map_pipeline?(calls) do
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

  # STEP 2: flatten pipeline into list of calls
  defp flatten_pipeline({:|>, _, [left, right]}) do
    flatten_pipeline(left) ++ [right]
  end

  defp flatten_pipeline(expr), do: [expr]

  # STEP 3: detect pattern in sequence
  defp grapheme_chunk_map_pipeline?(calls) do
    has_graphemes? =
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

    has_graphemes? and has_chunk? and has_map?
  end

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

        for i <- 0..String.length(string) - n do
          String.slice(string, i, n)
        end

    2. If Unicode safety is required:

        graphemes = String.graphemes(string)

        for i <- 0..length(graphemes) - n do
          graphemes |> Enum.slice(i, n) |> Enum.join()
        end

    3. Or redesign the algorithm to avoid rebuilding substrings entirely.
    """
  end
end
