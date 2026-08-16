defmodule Credence.Semantic.FixHallucinatedMapsetAny do
  @moduledoc """
  Fixes the compile warning for calls to the hallucinated `MapSet.any?/2`.

  `MapSet.any?/2` does not exist in Elixir — it is a common LLM hallucination.
  Because the `MapSet` module itself exists, the compiler emits a warning
  whose position points at the function name:

      "MapSet.any?/2 is undefined or private"

  `MapSet` implements `Enumerable`, so `Enum.any?/2` accepts a MapSet and is
  the intended call. The fix is a pure module rename: the flagged call's
  `MapSet` alias token is replaced with `Enum` via a Sourceror patch anchored
  at the diagnostic's line/column — the arguments (multi-line `fn` bodies
  included) and every other line survive byte-for-byte. Because a rename
  needs no structural rewrite, the direct `MapSet.any?(set, pred)`, the piped
  `set |> MapSet.any?(pred)`, and the capture `&MapSet.any?/2` are all fixed.

  Only messages that start with `MapSet.any?/2 is undefined or private` are
  claimed: a user module whose path merely ends in `MapSet`
  (`MyApp.MapSet.any?/2 …`) and other arities (`MapSet.any?/1`, whose intent
  — non-empty? any-truthy? — is ambiguous) stay unclaimed. The
  `Elixir.MapSet.any?(…)` spelling emits the same message but is deliberately
  left unfixed: the anchor only accepts an exact single-segment `MapSet`
  alias whose function name sits exactly at the flagged column, and the fix
  no-ops rather than risk a wrong edit (same policy as
  `FixHallucinatedEnumRange`). An `alias …, as: MapSet` spelling that
  resolves to another module never produces this message (the compiler
  reports the expanded module path), and a shadowed-but-valid call elsewhere
  in the file is protected by the anchor. The `should_report?/2` phase hook
  keeps `analyze` honest by reporting an issue only when `fix/2` would
  actually rewrite the source.

  ## Bad

      defmodule CredenceMapsetAnyReports do
        def has_active?(mapset, tombstones) do
          MapSet.any?(mapset, fn tag -> not MapSet.member?(tombstones, tag) end)
        end
      end

  ## Good

      defmodule CredenceMapsetAnyReports do
        def has_active?(mapset, tombstones) do
          Enum.any?(mapset, fn tag -> not MapSet.member?(tombstones, tag) end)
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @message_prefix "MapSet.any?/2 is undefined or private"

  # `MapSet.` — the diagnostic column points at `any?`, seven characters
  # after the start of the qualified call.
  @prefix_width 7

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.starts_with?(msg, @message_prefix)
  end

  def match?(_), do: false

  @doc """
  Phase hook (`Credence.Semantic.match_rules/2`): report an issue only when
  `fix/2` would actually rewrite the source. The same message is also emitted
  for the `Elixir.MapSet.any?(…)` spelling, which this rule deliberately does
  not rewrite.
  """
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_hallucinated_mapset_any,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         {:ok, alias_range} <- flagged_alias(ast, position(diagnostic)) do
      Sourceror.patch_string(source, [%{range: alias_range, change: "Enum"}])
    else
      _ -> source
    end
  end

  # The flagged call is the candidate whose function name sits exactly at the
  # diagnostic column. Without a column, a lone candidate on the flagged line
  # is unambiguous; anything else no-ops rather than guess.
  defp flagged_alias(ast, {line_no, col}) do
    candidates = candidates_on_line(ast, line_no)

    if is_integer(col) do
      case Enum.filter(candidates, fn range ->
             range.start[:column] + @prefix_width == col
           end) do
        [range] -> {:ok, range}
        _ -> :error
      end
    else
      case candidates do
        [range] -> {:ok, range}
        _ -> :error
      end
    end
  end

  # A candidate is the `MapSet` alias token of a `MapSet.any?` dot-call with
  # an exact single-segment `[:MapSet]` alias, starting on the flagged line.
  # The direct call carries two arguments, the piped form one, the capture
  # form zero — the rename is valid for all three, so all qualify;
  # `Elixir.MapSet` and multi-segment user aliases never do.
  defp candidates_on_line(ast, line_no) do
    {_, found} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:MapSet]} = alias_node, :any?]}, _, args} = node, acc
        when is_list(args) and length(args) <= 2 ->
          case Sourceror.get_range(alias_node) do
            %{start: start} = range ->
              if start[:line] == line_no, do: {node, [range | acc]}, else: {node, acc}

            nil ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  defp position(%{position: {line, col}}) when is_integer(line), do: {line, col}
  defp position(%{position: line}) when is_integer(line), do: {line, nil}
  defp position(_), do: {nil, nil}

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
