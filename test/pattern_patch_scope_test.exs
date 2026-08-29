defmodule Credence.PatternPatchScopeTest do
  @moduledoc """
  The byte-scope gate for the **Pattern** phase (docs/22 D2b) — the third and
  last shape of the same question.

  Syntax is covered by running a rule's `fix/1` over its own source
  (`self_corruption_test.exs`). Semantic is covered by comparing literals across
  a `fix/2` (`fix_byte_scope_test.exs`). Pattern returns patch **ranges**, so
  the question here is whether a range *splits* a literal — begins inside a
  masked run that started earlier, or ends inside one that continues past it.

  **The answer is zero**, and both of the obvious predicates are wrong:

    * "the range touches a masked byte" gives **70** hits, all false. Masking
      blanks a literal's delimiters too, so any patch replacing a whole literal
      lands on masked bytes at both ends — which is exactly what a rule
      rewriting `'abc'` to `~c"abc"` must do.
    * the splitting predicate, computed with **columns as bytes**, gives one
      hit, also false: `Keyword.get(opts, name: "café 🚀")` puts the offset
      inside the rocket emoji's continuation bytes. Sourceror columns are
      characters; masks are bytes.
  """
  use ExUnit.Case, async: false

  alias Credence.PatternPatchScope

  # EMPTY, and empty from the day it landed — so the controls carry the proof.
  @ledger []

  describe "no Pattern rule emits a patch that splits a literal" do
    @tag timeout: 600_000
    test "the ledger only grows by argument" do
      offenders = PatternPatchScope.offenders(PatternPatchScope.scan())

      assert offenders -- @ledger == [],
             """
             These rules emit a patch whose range starts or ends INSIDE a string,
             charlist, sigil or comment that continues past it — the patch cuts a
             literal in half and splices into the middle of it:

               #{Enum.map_join(offenders -- @ledger, "\n  ", &inspect/1)}

             A patch covering a WHOLE literal is fine and is not what this flags.
             """
    end
  end

  describe "byte_offset/3 — columns are characters, masks are bytes" do
    test "ASCII: column maps straight through" do
      assert PatternPatchScope.byte_offset("abc\ndef", 1, 1) == 0
      assert PatternPatchScope.byte_offset("abc\ndef", 2, 1) == 4
      assert PatternPatchScope.byte_offset("abc\ndef", 2, 3) == 6
    end

    # The measured false positive. Treating the column as a byte offset here
    # lands among the emoji's continuation bytes and reports a literal split.
    test "multi-byte: past an accented letter and an emoji" do
      src = ~S|Keyword.get(opts, name: "café 🚀")|

      assert String.length(src) == 33
      assert byte_size(src) == 37
      # column 34 is one past the last character; its byte offset is the full
      # byte length, not 33 — which is the entire point.
      assert PatternPatchScope.byte_offset(src, 1, 34) == 37
    end

    test "a line beyond the source is nil, not a crash" do
      assert PatternPatchScope.byte_offset("abc", 9, 1) == nil
    end
  end

  describe "the machinery is provable with the ledger empty" do
    @src ~S|x = foo("hello world")|

    defp scan(rules, source \\ @src), do: PatternPatchScope.scan(rules, fn _ -> [source] end)

    test "a patch that CUTS each masked construct in half is caught" do
      sources = [
        ~S|x = foo("hello world")|,
        ~S|x = foo('hello world')|,
        ~S|x = foo(~s(hello world))|,
        "x = \"\"\"\nhello world\n\"\"\"",
        "x = :ok # hello world"
      ]

      for source <- sources do
        assert [%{rule: PatchProbe.Splitter, fixture: ^source, side: side}] =
                 scan([PatchProbe.Splitter], source)

        assert side in [:start, :end]
      end
    end

    test "a patch covering a WHOLE literal is not" do
      assert scan([PatchProbe.WholeLiteral]) == []
    end

    test "a patch over ordinary code is not" do
      assert scan([PatchProbe.CodeOnly]) == []
    end

    test "a rule emitting no patches is not" do
      assert scan([PatchProbe.Silent]) == []
    end

    test "a raising rule is counted as an offender" do
      assert [%{rule: PatchProbe.Raiser, fixture: @src, side: :crashed}] ==
               scan([PatchProbe.Raiser])
    end
  end
end

# Fabricated rules — not `use Credence.Pattern.Rule`, so discovery can never
# find them. The scanner only calls `fix_patches/2`.
#
# `x = foo("hello world")` — the literal body spans columns 10..20 inclusive of
# its quotes at 9 and 21.
defmodule PatchProbe.Splitter do
  def fix_patches(_ast, source: source) do
    {offset, _length} = :binary.match(source, "hello world")

    # Both positions are inside "hello world", so the range cuts whichever
    # masked construct contains that marker.
    range = %{start: position(source, offset + 2), end: position(source, offset + 7)}
    [%{range: range, change: "X"}]
  end

  defp position(source, offset) do
    prefix = binary_part(source, 0, offset)
    lines = String.split(prefix, "\n")
    [line: length(lines), column: String.length(List.last(lines)) + 1]
  end
end

defmodule PatchProbe.WholeLiteral do
  def fix_patches(_ast, _opts) do
    # the whole literal including both quotes
    [%{range: %{start: [line: 1, column: 9], end: [line: 1, column: 22]}, change: ~s("bye")}]
  end
end

defmodule PatchProbe.CodeOnly do
  def fix_patches(_ast, _opts) do
    [%{range: %{start: [line: 1, column: 5], end: [line: 1, column: 8]}, change: "bar"}]
  end
end

defmodule PatchProbe.Silent do
  def fix_patches(_ast, _opts), do: []
end

defmodule PatchProbe.Raiser do
  def fix_patches(_ast, _opts), do: raise("probe")
end
