defmodule Credence.Semantic.FixHallucinatedStreamDataFlatMap do
  @moduledoc """
  Fixes the compile warning for calls to the hallucinated `StreamData.flat_map/2`.

  `StreamData.flat_map/2` does not exist — LLMs hallucinate it from the
  `flat_map`/`flatmap` naming other property-testing libraries use for the
  same operation. StreamData's name for it is `StreamData.bind/2`: take each
  generated value, run it through a function that returns a new generator.
  The argument order is identical, so the fix is a pure function rename.
  Because the `StreamData` module itself exists wherever the flagged code
  compiles, the compiler emits a warning whose position points at the
  function name:

      "StreamData.flat_map/2 is undefined or private"

  The flagged call's `flat_map` token is replaced with `bind` via a
  Sourceror patch anchored at the diagnostic's line/column — the arguments
  (multi-line `fn` bodies included) and every other line survive
  byte-for-byte. Because a rename needs no structural rewrite, the direct
  `StreamData.flat_map(gen, fun)`, the piped
  `gen |> StreamData.flat_map(fun)`, and the capture
  `&StreamData.flat_map/2` are all fixed.

  Only messages that start with `StreamData.flat_map/2 is undefined or
  private` are claimed: a user module whose path merely ends in `StreamData`
  (`MyApp.StreamData.flat_map/2 …`) and other arities stay unclaimed. The
  `Elixir.StreamData.flat_map(…)` spelling emits the same message but is
  deliberately left unfixed: the anchor only accepts an exact single-segment
  `StreamData` alias whose `flat_map` token sits exactly at the flagged
  column, and the fix no-ops rather than risk a wrong edit (same policy as
  `FixHallucinatedMapsetAny`). An `alias …, as: StreamData` spelling that
  resolves to another module never produces this message (the compiler
  reports the expanded module path), and a shadowed-but-valid call elsewhere
  in the file is protected by the anchor. The `should_report?/2` phase hook
  keeps `analyze` honest by reporting an issue only when `fix/2` would
  actually rewrite the source.

  `UndefinedFunction` claims every "… is undefined or private" message, this
  one included, but repairs by table lookup and has no row for
  `{"StreamData", "flat_map", 2}` — its `FunctionMatcher` fallback searches
  the flagged source for a module named `StreamData` and never finds one, so
  it returns the source unchanged and the rename to `bind` is lost. This rule
  keeps the default 500 against that rule's declared 501, so the ordering is
  declared — the catch-all yields to the specific claim (docs/20 §1) — rather
  than inherited from where the module names happen to sort.

  ## Bad

      defmodule CredenceStreamDataFlatMapReports do
        def sized_lists do
          StreamData.flat_map(StreamData.integer(1..10), fn len ->
            StreamData.list_of(StreamData.constant(len), length: len)
          end)
        end
      end

  ## Good

      defmodule CredenceStreamDataFlatMapReports do
        def sized_lists do
          StreamData.bind(StreamData.integer(1..10), fn len ->
            StreamData.list_of(StreamData.constant(len), length: len)
          end)
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @message_prefix "StreamData.flat_map/2 is undefined or private"

  # `StreamData.` — the diagnostic column points at `flat_map`, eleven
  # characters after the start of the qualified call.
  @prefix_width 11

  @name "flat_map"
  @name_width String.length(@name)

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.starts_with?(msg, @message_prefix)
  end

  def match?(_), do: false

  @doc """
  Phase hook (`Credence.Semantic.match_rules/2`): report an issue only when
  `fix/2` would actually rewrite the source. The same message is also emitted
  for the `Elixir.StreamData.flat_map(…)` spelling, which this rule
  deliberately does not rewrite.
  """
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_hallucinated_stream_data_flat_map,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         {:ok, name_range} <- flagged_name(source, ast, position(diagnostic)) do
      Sourceror.patch_string(source, [%{range: name_range, change: "bind"}])
    else
      _ -> source
    end
  end

  # The flagged call is the candidate whose `flat_map` token sits exactly at
  # the diagnostic column. Without a column, a lone candidate on the flagged
  # line is unambiguous; anything else no-ops rather than guess.
  defp flagged_name(source, ast, {line_no, col}) do
    candidates = candidates_on_line(source, ast, line_no)

    if is_integer(col) do
      case Enum.filter(candidates, fn range -> range.start[:column] == col end) do
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

  # A candidate is the `flat_map` token of a `StreamData.flat_map` dot-call
  # with an exact single-segment `[:StreamData]` alias, starting on the
  # flagged line. The direct call carries two arguments, the piped form one,
  # the capture form zero — the rename is valid for all three, so all
  # qualify; `Elixir.StreamData` and multi-segment user aliases never do.
  defp candidates_on_line(source, ast, line_no) do
    lines = String.split(source, "\n")

    {_, found} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:StreamData]} = alias_node, :flat_map]}, _, args} = node, acc
        when is_list(args) and length(args) <= 2 ->
          case Sourceror.get_range(alias_node) do
            %{start: start} ->
              if start[:line] == line_no do
                case name_range(lines, line_no, start[:column]) do
                  {:ok, range} -> {node, [range | acc]}
                  :error -> {node, acc}
                end
              else
                {node, acc}
              end

            nil ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  # The `flat_map` token's range is derived from the alias token's start
  # column, then verified against the source text — unusual spacing around
  # the dot (or any other column drift) fails the check and the fix no-ops
  # instead of patching the wrong bytes.
  defp name_range(lines, line_no, alias_col) do
    name_col = alias_col + @prefix_width
    line_text = Enum.at(lines, line_no - 1) || ""

    if String.slice(line_text, name_col - 1, @name_width) == @name do
      {:ok,
       %{
         start: [line: line_no, column: name_col],
         end: [line: line_no, column: name_col + @name_width]
       }}
    else
      :error
    end
  end

  defp position(%{position: {line, col}}) when is_integer(line), do: {line, col}
  defp position(%{position: line}) when is_integer(line), do: {line, nil}
  defp position(_), do: {nil, nil}

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
