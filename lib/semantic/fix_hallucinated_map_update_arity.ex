defmodule Credence.Semantic.FixHallucinatedMapUpdateArity do
  @moduledoc """
  Fixes the compile warning for calls to the hallucinated `Map.update/3`.

  `Map.update/3` does not exist in Elixir — LLMs hallucinate it from other
  languages' three-argument `update(map, key, fun)` (Clojure's `update`,
  lodash's `_.update`), dropping `Map.update/4`'s default argument:

      # Wrong (hallucinated):
      Map.update(counts, word, fn n -> n + 1 end)

      # Fixed (Map.update!/3):
      Map.update!(counts, word, fn n -> n + 1 end)

  The repair re-aims the call at `Map.update!/3`, the real function with the
  same argument list. For a present key it does exactly what every reading of
  the hallucinated call intends — apply the function to the current value. For
  a missing key it raises `KeyError`, a loud failure where the original code
  also failed loudly (`Map.update/3` is undefined, so the call could never
  return). No default is invented: any value this rule made up (a `0`, a
  `nil`, an empty list) would be silently wrong data for some caller — `0` is
  off-by-one even for the canonical word-count loop, and wrong-typed for a
  list accumulator — and silently-wrong beats loudly-missing on no input.

  The `!` is spliced into the flagged `update` token directly, so every other
  byte of the source survives untouched.

  Only messages that start with `Map.update/3 is undefined or private` are
  claimed: a user module whose path merely ends in `Map`
  (`MyApp.Map.update/3 …`) and other arities (`Map.update/2`, `/5`) stay with
  the generic `UndefinedFunction` rule. Shapes that emit the same message but
  admit no in-place token splice — `&Map.update/3` captures, the piped
  `x |> Map.update(key, fun)` (two arguments at the call site),
  `Elixir.Map.update(…)`, and a spelling that resolves to another module
  through `alias …, as: Map` — are deliberately left unfixed: the anchor only
  accepts a direct three-argument `Map.update(…)` call whose function name
  sits exactly at the flagged column, and the fix no-ops rather than risk a
  wrong edit (same policy as `FixHallucinatedMapPutArity`). A three-argument
  `Map.update` node that is the right-hand side of a `|>` is a *valid*
  `Map.update/4` call and is never a candidate. The `should_report?/2` phase
  hook keeps `analyze` honest by reporting an issue only when `fix/2` would
  actually rewrite the source.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @message_prefix "Map.update/3 is undefined or private"

  # `Map.` — the diagnostic column points at `update`, four characters after
  # the start of the qualified call.
  @prefix_width 4

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.starts_with?(msg, @message_prefix)
  end

  def match?(_), do: false

  @doc """
  Phase hook (`Credence.Semantic.match_rules/2`): report an issue only when
  `fix/2` would actually rewrite the source. The same message is also emitted
  for captures, piped calls, and alias-shadowed modules, which this rule
  deliberately does not rewrite.
  """
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_hallucinated_map_update_arity,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         {:ok, name_line, name_col} <- flagged_name(ast, position(diagnostic)),
         {:ok, patched} <- bang_update(source, name_line, name_col) do
      patched
    else
      _ -> source
    end
  end

  # The flagged call is the candidate whose function name sits exactly at the
  # diagnostic column. Without a column, a lone candidate on the flagged line
  # is unambiguous; anything else no-ops rather than guess.
  defp flagged_name(ast, {line_no, col}) when is_integer(line_no) do
    candidates = candidates_on_line(ast, line_no)

    if is_integer(col) do
      case Enum.filter(candidates, fn start -> start[:column] + @prefix_width == col end) do
        [_start] -> {:ok, line_no, col}
        _ -> :error
      end
    else
      case candidates do
        [start] -> {:ok, line_no, start[:column] + @prefix_width}
        _ -> :error
      end
    end
  end

  defp flagged_name(_ast, _position), do: :error

  # A candidate is a direct `Map.update(…)` call — exact `[:Map]` alias,
  # exactly three arguments — starting on the flagged line. The capture
  # (`&Map.update/3`, zero args in the dot call) and the piped hallucination
  # (`x |> Map.update(k, f)`, two args) never qualify, and a three-argument
  # node piped into (`x |> Map.update(k, d, f)`) is a valid `Map.update/4`
  # call, so pipe right-hand sides are excluded outright.
  defp candidates_on_line(ast, line_no) do
    {_, {calls, piped}} =
      Macro.prewalk(ast, {[], []}, fn
        {:|>, _, [_, rhs]} = node, {calls, piped} ->
          {node, {calls, [rhs | piped]}}

        {{:., _, [{:__aliases__, _, [:Map]}, :update]}, _, [_, _, _]} = node, {calls, piped} ->
          {node, {[node | calls], piped}}

        node, acc ->
          {node, acc}
      end)

    calls
    |> Enum.reverse()
    |> Enum.reject(fn node -> node in piped end)
    |> Enum.flat_map(fn node ->
      case Sourceror.get_range(node) do
        %{start: start} -> if start[:line] == line_no, do: [start], else: []
        nil -> []
      end
    end)
  end

  # Splice the `!` into the flagged line. Columns are codepoint-based (the
  # tokenizer's unit, shared by the diagnostic and Sourceror), so the line is
  # handled as a charlist; requiring the six codepoints at the flagged column
  # to be exactly `update` keeps unusual spellings (`Map . update(…)`, a name
  # on the next line) from being spliced at the wrong spot — they no-op.
  defp bang_update(source, line_no, col) do
    lines = String.split(source, "\n")

    with line when is_binary(line) <- Enum.at(lines, line_no - 1),
         {prefix, ~c"update" ++ rest} <- Enum.split(String.to_charlist(line), col - 1) do
      new_line = List.to_string(prefix ++ ~c"update!" ++ rest)
      {:ok, lines |> List.replace_at(line_no - 1, new_line) |> Enum.join("\n")}
    else
      _ -> :error
    end
  end

  defp position(%{position: {line, col}}) when is_integer(line), do: {line, col}
  defp position(%{position: line}) when is_integer(line), do: {line, nil}
  defp position(_), do: {nil, nil}

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
