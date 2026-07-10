defmodule Credence.Syntax.NoMixedScriptIdentifier do
  @moduledoc """
  Removes defmodule blocks whose identifier mixes Unicode scripts without an
  underscore separator.

  LLMs (especially Qwen) repeatedly hallucinate duplicate module definitions
  where CJK characters merge into the identifier — e.g. `defmodule补偿State`
  or `defmodule补偿Step`. Elixir's tokenizer rejects mixed-script identifiers
  ("invalid mixed-script identifier found") for security reasons: different
  Unicode scripts must be separated by `_`.

  Because the hallucinated block is always a duplicate of a valid defmodule
  already present in the same file, the fix removes the offending block
  entirely. Detection is parser-driven: `Code.string_to_quoted/1` returns the
  error with the exact line and token, so no regex heuristics are needed to
  locate the fault.

  ## Bad (won't parse — mixed-script identifier)

      defmodule Saga do
        def hello, do: :world
      end

      defmodule补偿State do
        def hello, do: :world
      end

  ## Good

      defmodule Saga do
        def hello, do: :world
      end
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @impl true
  def analyze(source) do
    case detect(source) do
      {:ok, line, _token} ->
        [
          %Issue{
            rule: :no_mixed_script_identifier,
            message:
              "Mixed-script identifier — Elixir requires different Unicode scripts be separated by underscores.",
            meta: %{line: line}
          }
        ]

      :none ->
        []
    end
  end

  @impl true
  def fix(source) do
    case detect(source) do
      {:ok, line, _token} -> remove_block_at(source, line)
      :none -> source
    end
  end

  # --- detection ---------------------------------------------------------------

  defp detect(source) do
    case Code.string_to_quoted(source) do
      {:error, {meta, message, token}} when is_list(meta) ->
        if mixed_script_error?(message) do
          {:ok, Keyword.get(meta, :line), token}
        else
          :none
        end

      _ ->
        :none
    end
  end

  defp mixed_script_error?(message) when is_binary(message) do
    String.contains?(message, "invalid mixed-script identifier found")
  end

  defp mixed_script_error?({part1, part2}) do
    mixed_script_error?(part1) or mixed_script_error?(part2)
  end

  defp mixed_script_error?(_), do: false

  # --- block removal -----------------------------------------------------------

  defp remove_block_at(source, line) do
    lines = String.split(source, "\n")
    start_idx = line - 1
    end_idx = find_matching_end(lines, start_idx)

    # Drop the block and any single blank line immediately after it (the visual
    # separator the LLM placed between the valid and hallucinated modules).
    drop_through =
      if end_idx + 1 < length(lines) and blank?(Enum.at(lines, end_idx + 1)),
        do: end_idx + 1,
        else: end_idx

    {before, rest} = Enum.split(lines, start_idx)
    after_block = Enum.drop(rest, drop_through - start_idx + 1)
    Enum.join(before ++ after_block, "\n")
  end

  # Walk forward from `start_idx`, counting `do`/`end` nesting, and return the
  # index of the `end` that closes the outermost block. The `do` keyword on the
  # opening line is depth 1; nested `do` blocks increment; each `end` decrements.
  defp find_matching_end(lines, start_idx) do
    do_end_depth(lines, start_idx, 0)
  end

  defp do_end_depth(lines, idx, _depth) when idx >= length(lines), do: idx - 1

  defp do_end_depth(lines, idx, depth) do
    line = Enum.at(lines, idx)

    # Count block-opening `do` — but NOT `do:` (keyword syntax in function heads).
    do_count = Regex.scan(~r/(?<!\:)\bdo\b(?!\:)/, line) |> length()
    end_count = Regex.scan(~r/\bend\b/, line) |> length()

    new_depth = depth + do_count - end_count

    if depth > 0 and new_depth == 0 do
      idx
    else
      do_end_depth(lines, idx + 1, new_depth)
    end
  end

  defp blank?(line), do: String.trim(line) == ""
end
