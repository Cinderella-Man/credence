defmodule Credence.Semantic.PreferExplicitRangeStep do
  @moduledoc """
  Makes the implicit step of a descending literal range explicit.

  Since Elixir 1.19 a fully-literal range whose default step is `-1`
  (`first > last`, e.g. `1..-2`, `10..-5`, `5..1`) emits a deprecation warning:

      1..-2 has a default step of -1, please write 1..-2//-1 instead

  Under `--warnings-as-errors` this blocks compilation. The fix appends `//-1`,
  which is a **no-op on behaviour**: the warning states that `-1` is already the
  current default step, so `1..-2` and `1..-2//-1` are the identical `Range`
  value.

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

  ## Bad

      defmodule PreferExplicitRangeStepPipelineFixture do
        def f(l), do: {Enum.slice(l, 1..-2), "label 1..-2"}
        def g(l), do: Enum.take(l, 5..1)
      end

  ## Good

      defmodule PreferExplicitRangeStepPipelineFixture do
        def f(l), do: {Enum.slice(l, 1..-2//-1), "label 1..-2"}
        def g(l), do: Enum.take(l, 5..1//-1)
      end
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

  # Parse the source and append an explicit `//-1` step to every descending
  # literal range operator node. Patching is range-targeted (Sourceror replaces
  # only the bytes of each `..` node), so the rest of the source — including any
  # string/atom/comment that merely contains the same digits — is byte-for-byte
  # preserved. Unparseable source is left untouched.
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

  defp collect_ranges(ast) do
    {_ast, ranges} =
      Macro.prewalk(ast, [], fn
        {:.., _meta, [lo, hi]} = node, acc ->
          case {literal_int(lo), literal_int(hi)} do
            {{:ok, a}, {:ok, b}} when a > b -> {node, [node | acc]}
            _ -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    ranges
  end

  defp patch(node) do
    %{range: Sourceror.get_range(node), change: &(&1 <> "//-1")}
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
