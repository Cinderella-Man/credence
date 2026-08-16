defmodule Credence.PatternPatchScope do
  @moduledoc """
  The byte-scope oracle for the **Pattern** phase (docs/22 D2b).

  `SelfCorruption` covers Syntax (a rule's `fix/1` over its own source) and
  `FixByteScope` covers Semantic (a literal that survives a `fix/2` with changed
  content). Pattern needs a third shape, because a Pattern rule returns **patch
  ranges** rather than a new source: the question is whether a range *splits* a
  literal.

  ## The predicate, and the two that do not work

  Covering a whole literal is legitimate and common — a rule replacing `'abc'`
  with `~c"abc"` patches exactly that node. `SourceMask.mask/1` blanks a
  literal's *delimiters* along with its body, so such a patch necessarily starts
  and ends on masked bytes. Flagging that gives 70 hits, all false.

  The bug shape is a range that begins inside a masked run which started
  *earlier*, or ends inside one that continues *past* it — i.e. the patch cuts a
  literal in half and splices something into the middle of it.

  ## Columns are characters; masks are bytes

  `Sourceror.Range` positions are 1-based **character** columns. `mask/1`
  preserves **byte** length. Comparing the two directly puts the offset inside a
  multi-byte character on any fixture containing one — measured: it accused
  `NoKeywordGetKeywordKey` of splitting a literal on
  `Keyword.get(opts, name: "café 🚀")`, where the computed offset landed among
  the rocket emoji's continuation bytes. `byte_offset/3` converts.
  """

  alias Credence.SourceMask

  @doc """
  `[%{rule:, fixture:, range:, side:}]` — one entry per patch whose range splits
  a literal. Takes its rule list and fixture source as arguments so the controls
  can drive fabricated rules with the ledger empty.
  """
  @spec scan([module()], (module() -> [String.t()])) :: [map()]
  def scan(rules \\ Credence.Pattern.default_rules(), candidates \\ &default_candidates/1) do
    Enum.flat_map(rules, fn rule ->
      rule |> candidates.() |> Enum.flat_map(&split_patches(rule, &1))
    end)
  end

  @doc false
  def default_candidates(rule), do: Credence.PipelineWitness.candidates(rule)

  defp split_patches(rule, source) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         patches when is_list(patches) <- safe_patches(rule, ast, source) do
      mask = SourceMask.mask(source)
      Enum.flat_map(patches, &check_range(rule, source, mask, &1))
    else
      _ -> []
    end
  rescue
    _ -> []
  catch
    _, _ -> []
  end

  defp safe_patches(rule, ast, source) do
    rule.fix_patches(ast, source: source)
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end

  defp check_range(rule, source, mask, %{range: %{start: s, end: e}}) do
    with a when is_integer(a) <- byte_offset(source, s[:line], s[:column]),
         b when is_integer(b) <- byte_offset(source, e[:line], e[:column]) do
      cond do
        masked_at?(mask, a) and masked_at?(mask, a - 1) ->
          [%{rule: rule, fixture: source, range: %{start: s, end: e}, side: :start}]

        masked_at?(mask, b - 1) and masked_at?(mask, b) ->
          [%{rule: rule, fixture: source, range: %{start: s, end: e}, side: :end}]

        true ->
          []
      end
    else
      _ -> []
    end
  end

  defp check_range(_rule, _source, _mask, _patch), do: []

  defp masked_at?(_mask, i) when i < 0, do: false

  defp masked_at?(mask, i) when i < byte_size(mask), do: :binary.at(mask, i) == 0x01

  defp masked_at?(_mask, _i), do: false

  @doc """
  Byte offset of the 1-based `line`/`column` character position in `source`.

  This is the whole reason this module is not four lines long.
  """
  @spec byte_offset(String.t(), pos_integer(), pos_integer()) :: non_neg_integer() | nil
  def byte_offset(source, line, column) when is_integer(line) and is_integer(column) do
    lines = String.split(source, "\n")

    if line <= length(lines) do
      prefix_bytes =
        lines |> Enum.take(line - 1) |> Enum.reduce(0, fn l, acc -> acc + byte_size(l) + 1 end)

      target = Enum.at(lines, line - 1) || ""
      within = target |> String.graphemes() |> Enum.take(column - 1) |> IO.iodata_to_binary()
      prefix_bytes + byte_size(within)
    end
  end

  def byte_offset(_source, _line, _column), do: nil

  @doc "The distinct rules with at least one splitting patch."
  @spec offenders([map()]) :: [module()]
  def offenders(entries), do: entries |> Enum.map(& &1.rule) |> Enum.uniq() |> Enum.sort()
end
