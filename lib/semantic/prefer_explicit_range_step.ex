defmodule Credence.Semantic.PreferExplicitRangeStep do
  @moduledoc """
  Makes the implicit step of a descending literal range explicit.

  Since Elixir 1.19 a fully-literal range whose default step is `-1`
  (`first > last`, e.g. `1..-2`, `10..-5`, `5..1`) emits a deprecation warning:

      1..-2 has a default step of -1, please write 1..-2//-1 instead

  Under `--warnings-as-errors` this blocks compilation. The fix appends an
  explicit step, which is a **no-op on behaviour** for most ranges: the warning
  states that `-1` is already the current default step, so `1..-2` and
  `1..-2//-1` are the identical `Range` value.

  ### Special case: "to end" ranges (`first..-1`)

  When the upper bound is `-1` — the idiomatic "to end" range used in
  `String.slice/2`, `Enum.slice/2`, etc. — the fix appends `//1` (positive
  step) instead of `//-1`. A negative step on a "to end" range would reverse
  and truncate the slice, producing wrong results at runtime:

      String.slice(str, 3..-1)     # "from index 3 to end"
      String.slice(str, 3..-1//-1) # WRONG: reversed/truncated
      String.slice(str, 3..-1//1)  # correct: same as the original

  ## Why the fix is AST-based, not text-based

  The diagnostic carries **no usable position** — `Code.with_diagnostics`
  reports the range-step deprecation at position `0`, with no line or column —
  and the message **normalizes whitespace** (a source range `1 .. -2` is
  reported as `1..-2`). A text-replacement fix keyed on the message string would
  therefore (a) miss spaced ranges entirely and (b) blindly rewrite *every*
  occurrence of that text — including the same digits sitting inside a string
  literal, atom, or comment — silently changing a value. That is a behaviour
  change, not a no-op.

  Instead the fix parses the source and rewrites only genuine range *operator*
  nodes (`{:.., _, [lo, hi]}`) whose two endpoints are integer literals (or the
  unary minus of one) with `lo > hi` — exactly the inputs the compiler warns on,
  and the only inputs for which the default step is `-1`. Strings, charlists,
  atoms and comments carry no `..` operator node, so they are never touched. A
  range with a non-literal endpoint (`a..-1`) produces no diagnostic and matches
  no node, so it is left alone.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, "has a default step of") and
      String.contains?(msg, "please write")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :prefer_explicit_range_step,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) when is_binary(msg) do
    if match?(%{severity: :warning, message: msg}) do
      patch_descending_ranges(source)
    else
      source
    end
  end

  def fix(source, _diagnostic), do: source

  # Parse the source and append an explicit step to every descending
  # literal range operator node. When the upper bound is `-1` (the idiomatic
  # "to end" range), appends `//1`; otherwise appends `//-1`.
  # Patching is range-targeted (Sourceror replaces only the bytes of each `..`
  # node), so the rest of the source — including any string/atom/comment that
  # merely contains the same digits — is byte-for-byte preserved. Unparseable
  # source is left untouched.
  defp patch_descending_ranges(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        case collect_ranges(ast) do
          [] -> source
          ranges -> Sourceror.patch_string(source, Enum.map(ranges, &patch/1))
        end

      _ ->
        source
    end
  end

  # Collects descending literal range nodes together with their upper-bound
  # value so patch/1 can decide the correct explicit step.
  defp collect_ranges(ast) do
    {_ast, ranges} =
      Macro.prewalk(ast, [], fn
        {:.., _meta, [lo, hi]} = node, acc ->
          case {literal_int(lo), literal_int(hi)} do
            {{:ok, a}, {:ok, b}} when a > b -> {node, [{node, b} | acc]}
            _ -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    ranges
  end

  # When the upper bound is -1 (the "to end" idiom), the correct explicit step
  # is `//1` (positive). A negative step would reverse and truncate the slice.
  # For all other descending ranges, the explicit step is `//-1`.
  defp patch({node, hi_val}) do
    step = if hi_val == -1, do: "//1", else: "//-1"
    %{range: Sourceror.get_range(node), change: &(&1 <> step)}
  end

  # The endpoints the compiler can fold to a default step of -1: an integer
  # literal, or the unary minus of one. Anything else (a variable, a call, an
  # attribute) yields no compile-time step and so no deprecation — skip it.
  defp literal_int({:__block__, _, [n]}) when is_integer(n), do: {:ok, n}
  defp literal_int(n) when is_integer(n), do: {:ok, n}

  defp literal_int({:-, _, [inner]}) do
    case literal_int(inner) do
      {:ok, n} -> {:ok, -n}
      :error -> :error
    end
  end

  defp literal_int(_), do: :error

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
