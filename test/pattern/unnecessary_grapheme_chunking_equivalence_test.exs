defmodule Credence.Pattern.UnnecessaryGraphemeChunkingEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.UnnecessaryGraphemeChunking

  # Firing snippets lifted from unnecessary_grapheme_chunking_check_test.exs:
  #   defmodule Example do
  #       def ngrams(string, n) do
  #         string
  #         |> String.graphemes()
  #         |> Enum.chunk_every(n, 1, :discard)
  #         |> Enum.map(&Enum.join/1)
  #       end
  #     end
  #   defmodule Example do
  #       def ngrams(string, n) do
  #         string
  #         |> String.graphemes()
  #         |> Enum.chunk_every(n, 1, :discard)
  #         |> Enum.map(fn chunk -> Enum.join(chunk) end)
  #       end
  #     end
  #   defmodule Example do
  #       def ngrams(string, n) do
  #         string
  #         |> String.graphemes()
  #         |> Enum.chunk_every(n, 1, :discard)
  #         |> Enum.map(fn x -> Enum.join(x, "") end)
  #       end
  #     end

  test "unnecessary_grapheme_chunking: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: UnnecessaryGraphemeChunking,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
