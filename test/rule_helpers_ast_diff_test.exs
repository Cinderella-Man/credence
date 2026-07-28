defmodule Credence.RuleHelpersAstDiffTest do
  @moduledoc """
  The AST differ behind `Credence.RuleHelpers`' three patch-producing entry
  points had no test of its own until 2026-07-28 (docs/22 T5.10) — the same gap,
  in the same shape, that `Credence.SourceMask` had until the day before. It is a
  poor place for one: `diff_patches/2` sits under all 157 Pattern rules, so a
  range that is off by a single column is a population-wide corruption, and the
  rules it corrupts are the ones a weak model will write next.

  The defect these pin is the bracket arithmetic of a list literal. Sourceror
  parses `[:a, :b, :c]` as `{:__block__, meta, [[…]]}`, and **only the wrapper
  carries the bracket positions** — `line`/`column` for the `[`, `closing` for
  the `]`. The bare list underneath has no metadata at all, so its range is
  synthesized from its first and last elements and comes out
  bracket-*exclusive*, while `Sourceror.to_string/1` renders a list
  bracket-*inclusive*. Patch at the bare list and the brackets are written twice:

      call(:name, [:a, :b, :c])  ->  call(:name, [[:a, :c]])

  **Why nothing caught it for so long.** `[[:a, :c]]` parses and preserves every
  comment, so the safety invariants in `apply_rule_fix_with_status/3` pass it
  through unchanged. A corrupting patch that still parses is the one that ships;
  the stranded-delimiter kind is the one that gets rejected. In T5.9 this very
  defect hit two fixtures of one rule — the invariants rejected one
  (`:patch_rejected`, silently) and shipped the other.

  The invariant worth stating once, since every case below is an instance of it:
  **a patch's range and its replacement text must agree about who owns the
  delimiters.** The last test states it as a property rather than as an example.
  """
  use ExUnit.Case, async: true

  alias Credence.RuleHelpers

  # Drop the middle element of any 3-element literal list; leave all else alone.
  defp drop_middle do
    fn
      {:__block__, meta, [[a, _b, c]]} -> {:__block__, meta, [[a, c]]}
      other -> other
    end
  end

  defp parse!(source), do: Sourceror.parse_string!(source)

  defp patch(source, patches), do: Sourceror.patch_string(source, patches)

  # Compare *meaning*, not text. Asserting on rendered strings is what hid four
  # earlier defects in this program (docs/21); two sources are equivalent here
  # when they parse to the same tree ignoring layout metadata.
  defp meaning(source) do
    source
    |> Code.string_to_quoted!()
    |> Macro.prewalk(fn
      {form, meta, args} when is_list(meta) -> {form, [], args}
      other -> other
    end)
  end

  describe "a bracketed list literal — the T5.10 defect" do
    @source """
    defmodule M do
      def go do
        call(:name, [:a, :b, :c])
      end
    end
    """

    test "patches_from_postwalk/2 covers the brackets, not one column inside them" do
      ast = parse!(@source)
      [%{range: range}] = RuleHelpers.patches_from_postwalk(ast, drop_middle())

      # The `[` is at column 17 of line 3. The defect emitted 18.
      assert range.start[:column] == 17
      assert range.start[:line] == 3
    end

    test "patches_from_postwalk/2 does not double-wrap the list" do
      ast = parse!(@source)
      patches = RuleHelpers.patches_from_postwalk(ast, drop_middle())

      assert patch(@source, patches) =~ "call(:name, [:a, :c])"
      refute patch(@source, patches) =~ "[["
    end

    test "patches_from_ast_transform/3 — the same, through the other entry point" do
      ast = parse!(@source)

      patches =
        RuleHelpers.patches_from_ast_transform(ast, @source, &Macro.postwalk(&1, drop_middle()))

      assert patch(@source, patches) =~ "call(:name, [:a, :c])"
      refute patch(@source, patches) =~ "[["
    end

    test "patches_from_diff/2 — and through the third" do
      ast = parse!(@source)
      transformed = Macro.postwalk(ast, drop_middle())
      patches = RuleHelpers.patches_from_diff(ast, transformed)

      assert patch(@source, patches) =~ "call(:name, [:a, :c])"
      refute patch(@source, patches) =~ "[["
    end

    test "the double-wrapped output parses — which is why the safety net missed it" do
      # Not a test of the fix; a test of *why the fix had to exist*. If this ever
      # stops parsing, the invariants would have caught the defect on their own
      # and this whole file is less load-bearing than its moduledoc claims.
      assert {:ok, _} = Code.string_to_quoted("call(:name, [[:a, :c]])")
    end
  end

  describe "what the fix must not break" do
    test "a same-length element change still patches at the element, not the list" do
      source = """
      defmodule M do
        def go do
          call(:name, [:a, :b, :c])
        end
      end
      """

      ast = parse!(source)

      patches =
        RuleHelpers.patches_from_postwalk(ast, fn
          {:__block__, meta, [:b]} -> {:__block__, meta, [:z]}
          other -> other
        end)

      # Tight: the patch covers `:b` (column 22 — the `[` is at 17, `:a` at 18)
      # alone, leaving the brackets and the sibling elements' source bytes
      # untouched. Widening this to the whole list would reformat lists that
      # rules never meant to reformat.
      assert [%{range: range, change: ":z"}] = patches
      assert range.start[:column] == 22
      assert patch(source, patches) =~ "call(:name, [:a, :z, :c])"
    end

    test "a nested list edit lands at the inner list's own brackets" do
      source = """
      defmodule M do
        def go do
          call(:name, [[:a, :b, :c], :d])
        end
      end
      """

      ast = parse!(source)
      patches = RuleHelpers.patches_from_postwalk(ast, drop_middle())

      assert patch(source, patches) =~ "call(:name, [[:a, :c], :d])"
    end

    test "emptying a list keeps the brackets exactly once" do
      source = """
      defmodule M do
        def go do
          call(:name, [:a])
        end
      end
      """

      ast = parse!(source)

      patches =
        RuleHelpers.patches_from_postwalk(ast, fn
          {:__block__, meta, [[_one]]} -> {:__block__, meta, [[]]}
          other -> other
        end)

      assert patch(source, patches) =~ "call(:name, [])"
    end

    test "replacing a list with a non-list removes the brackets with it" do
      source = """
      defmodule M do
        def go do
          call(:name, [:a, :b])
        end
      end
      """

      ast = parse!(source)

      patches =
        RuleHelpers.patches_from_postwalk(ast, fn
          {:__block__, _meta, [[_, _]]} -> {:opts, [], nil}
          other -> other
        end)

      # The brackets belong to the node being replaced, so they go with it.
      assert patch(source, patches) =~ "call(:name, opts)"
      refute patch(source, patches) =~ "[opts]"
    end

    test "rewrap_list/2 — the idiom rules use — round-trips through the differ" do
      source = """
      defmodule M do
        def go do
          :ets.new(:t, [:set, :public, :named_table])
        end
      end
      """

      ast = parse!(source)

      patches =
        RuleHelpers.patches_from_postwalk(ast, fn
          {:__block__, _, [[_ | _] = els]} = node when length(els) == 3 ->
            RuleHelpers.rewrap_list(node, Enum.take(els, 2))

          other ->
            other
        end)

      assert patch(source, patches) =~ ":ets.new(:t, [:set, :public])"
    end
  end

  describe "the unbracketed sibling — recorded, not repaired" do
    test "a trailing keyword list gains brackets, and that is layout-only" do
      # A trailing keyword list has no brackets in the source, so its
      # synthesized range is *correct* — but `Sourceror.to_string/1` still
      # renders one bracket-inclusive, so an element removal inserts brackets
      # that were never there. Unlike the wrapped case this is not a
      # corruption: the output parses and means exactly the same thing. It is
      # pinned here so the next reader can tell the two apart instead of
      # rediscovering this one and assuming T5.10 regressed.
      source = "call(:name, a: 1, b: 2)\n"
      ast = parse!(source)

      patches =
        RuleHelpers.patches_from_postwalk(ast, fn
          [_first, _second] = pairs when is_list(pairs) -> [hd(pairs)]
          other -> other
        end)

      applied = patch(source, patches)

      assert applied == "call(:name, [a: 1])\n"
      assert meaning(applied) == meaning("call(:name, a: 1)\n")
    end
  end

  describe "the property behind all of the above" do
    test "for every list edit, the patched source means what the transform said" do
      # The examples above assert on text. This asserts the invariant they are
      # instances of: applying the emitted patches yields source that parses to
      # the transform's own output. A range/replacement disagreement about the
      # delimiters shows up here as a tree mismatch regardless of spelling.
      sources = [
        "call(:name, [:a, :b, :c])\n",
        "call(:name, [[:a, :b, :c], :d])\n",
        "x = [:a, :b, :c]\n",
        "%{opts: [:a, :b, :c]}\n",
        "call(:name, [:a, :b, :c], other)\n",
        "def f, do: g([:a, :b, :c])\n",
        "[[:a, :b, :c]]\n"
      ]

      for source <- sources do
        ast = parse!(source)
        transformed = Macro.postwalk(ast, drop_middle())
        patches = RuleHelpers.patches_from_diff(ast, transformed)
        applied = patch(source, patches)

        assert {:ok, _} = Code.string_to_quoted(applied),
               "patched source does not parse for #{inspect(source)}: #{inspect(applied)}"

        assert meaning(applied) == meaning(Sourceror.to_string(transformed)),
               "patched source does not match the transform for #{inspect(source)}: " <>
                 "#{inspect(applied)} vs #{inspect(Sourceror.to_string(transformed))}"
      end
    end
  end
end
