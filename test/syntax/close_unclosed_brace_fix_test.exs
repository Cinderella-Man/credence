defmodule Credence.Syntax.CloseUnclosedBraceFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.CloseUnclosedBrace

  defp analyze(code), do: CloseUnclosedBrace.analyze(code)
  defp fix(code), do: CloseUnclosedBrace.fix(code)

  test "fixes unclosed tuple brace before end" do
    input = """
    defmodule Example do
      use GenServer

      def init(_opts) do
        {:ok, %{key: "value"}
      end
    end
    """

    expected = """
    defmodule Example do
      use GenServer

      def init(_opts) do
        {:ok, %{key: "value"}}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    code = """
    defmodule Example do
      use GenServer

      def init(_opts) do
        {:ok, %{key: "value"}
      end
    end
    """

    assert analyze(fix(code)) == []
  end

  test "fixed output is well-formed (parses)" do
    code = """
    defmodule Example do
      use GenServer

      def init(_opts) do
        {:ok, %{key: "value"}
      end
    end
    """

    assert valid_syntax?(fix(code))
  end

  test "does not modify already-valid code" do
    code = """
    defmodule Example do
      def init(_opts) do
        {:ok, %{key: "value"}}
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "fixes unclosed map brace before end" do
    input = """
    defmodule Example do
      def foo do
        %{key: "value"
      end
    end
    """

    expected = """
    defmodule Example do
      def foo do
        %{key: "value"}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "closes a literal spread over several lines on its last line" do
    input = """
    defmodule Example do
      def foo do
        {:ok,
         1
      end
    end
    """

    expected = """
    defmodule Example do
      def foo do
        {:ok,
         1}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "closes a multi-line map on its last entry" do
    input = """
    defmodule Example do
      def foo do
        %{
          a: 1,
          b: 2
      end
    end
    """

    expected = """
    defmodule Example do
      def foo do
        %{
          a: 1,
          b: 2}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "adds as many closing braces as the nesting needs" do
    input = """
    defmodule Example do
      def foo do
        {:ok, %{a: %{b: 1
      end
    end
    """

    expected = """
    defmodule Example do
      def foo do
        {:ok, %{a: %{b: 1}}}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "closes an unclosed struct literal" do
    input = """
    defmodule Example do
      def foo do
        %User{name: "a"
      end
    end
    """

    expected = """
    defmodule Example do
      def foo do
        %User{name: "a"}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "closes a tuple inside an fn body" do
    input = """
    defmodule Example do
      def foo(list) do
        Enum.map(list, fn x ->
          {x, x
        end)
      end
    end
    """

    expected = """
    defmodule Example do
      def foo(list) do
        Enum.map(list, fn x ->
          {x, x}
        end)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "skips a blank line and closes on the literal's last content line" do
    input = """
    defmodule Example do
      def foo do
        x = {1, 2

      end
    end
    """

    expected = """
    defmodule Example do
      def foo do
        x = {1, 2}

      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  # --- the cases the check deliberately skips are left byte-for-byte alone ---
  #
  # Byte-for-byte in their internal layout: `confirm_fix/2` compares with
  # trailing newlines trimmed off both sides, so the file's final newline is
  # pinned by the last test in this file rather than by these.

  test "leaves an ambiguous placement untouched" do
    code = """
    defmodule Example do
      def foo do
        x = {1, 2
        IO.puts(x)
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves an operator-continuation ambiguity untouched" do
    # Both placements parse and mean different things: `x = {1, 2}` piped
    # into IO.inspect, or the tuple `{1, 2 |> IO.inspect()}`. The rule must
    # refuse rather than silently commit one of the two meanings.
    code = """
    defmodule Example do
      def foo do
        x = {1, 2
        |> IO.inspect()
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves a placement split across two lines untouched" do
    # Two readings of the truncated source parse and mean different things:
    # both missing braces at the end (`{1, {2, {3}, 5}}`), or the inner one a
    # line up and only the outer at the end (`{1, {2, {3}}, 5}`). The rule
    # must refuse rather than silently commit one of the two meanings.
    code = """
    defmodule Example do
      def foo do
        x = {1, {2, {3
        }, 5
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves a nesting that opens on two lines untouched" do
    # The parser names only the innermost `{` still open — line 4 here — so
    # line 3, where the outer `{` sits, is the first line a competing `}` could
    # belong to. Both readings parse and differ: `{1 ++ %{a: 2}}` is a
    # one-element tuple, `{1} ++ %{a: 2}` concatenates a tuple and a map. The
    # rule must refuse rather than silently commit one of them.
    code = """
    defmodule Example do
      def foo do
        x = {1
        ++ %{a: 2
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves an earlier line that swallows the brace in a comment untouched" do
    # Appending a `}` to line 3 puts it inside the comment, so we cannot tell
    # whether the brace belonged there — the same doubt as a competing
    # placement, and refused for the same reason. (Committing would turn the
    # author's likely `{1} |> g()` into `{1 |> g()}`.)
    code = """
    defmodule Example do
      def foo do
        x = {1 # }
        |> g()
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves an earlier line whose comment ends in a comma untouched" do
    # Same shape as the test above — a `}` appended to line 3 disappears into
    # the comment — but the comment's last character is a `,`. A comma pins the
    # next line inside the literal only when it is a comma in *code*; this one
    # is prose, and treating it as code skipped the swallowed-brace probe
    # entirely. Both readings still parse and differ (`{1 |> g()}` against the
    # author's likely `{1} |> g()`), so the rule must refuse.
    code = """
    defmodule Example do
      def foo do
        x = {1 # oops,
        |> g()
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves an operator ambiguity on the literal's own line untouched" do
    # The literal opens on the very line the `}` is appended to, so there is no
    # earlier line to probe — the placement has to be weighed *within* the line.
    # `x = {1, 2} |> IO.inspect()` and `x = {1, 2 |> IO.inspect()}` both parse
    # and mean different things, exactly as in the two-line form above, so the
    # rule must refuse here too rather than let the answer depend on where the
    # author happened to break the line.
    code = """
    defmodule Example do
      def foo do
        x = {1, 2 |> IO.inspect()
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves a mid-line ambiguity on the literal's last line untouched" do
    # The same doubt on a literal that does span two lines: the `}` could sit
    # after the `2` (`{1, 2} |> IO.inspect()`) instead of at the end of the
    # line. The line above ends in `,` and is skipped, so nothing but a
    # within-the-line placement can catch this one.
    code = """
    defmodule Example do
      def foo do
        x = {1,
        2 |> IO.inspect()
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "commits nothing that a brace split over other lines could also mean" do
    # The rule only ever weighs the missing braces shared between ONE earlier
    # line and the target line, and its source says those shares "are the whole
    # alternative set". A reading that spreads the braces over two *different*
    # earlier lines is therefore never tried, and the hand-written cases above
    # would not notice one. This searches for such a source: every three-line
    # function body built from the fragments below, and for each body the rule
    # does repair, every way of spreading the same braces over the body's lines
    # using at least two of them. Any such rival that parses is a second meaning
    # the rule discarded silently — the one failure it promises never to make.
    #
    # Every completion appends exactly as many `}` as there are `{` still open,
    # because a `}` only ever closes one, so rivals with a different total are
    # not readings of the same source and are not searched.
    sources =
      for a <- brace_fragments(), b <- brace_fragments(), c <- brace_fragments() do
        "defmodule Example do\n  def foo do\n    x = " <>
          Enum.join([a, b, c], "\n    ") <> "\n  end\nend\n"
      end

    repaired =
      sources
      |> Enum.map(&{&1, fix(&1)})
      |> Enum.reject(fn {source, fixed} -> fixed == source end)

    # Every completion this search puts to the parser. Counting *repairs* would
    # be the wrong vacuity guard: a source the rule repaired with a single `}`
    # has no rival at all — one brace cannot be spread over two lines — so
    # `brace_splits/2` returns nothing for it and it is searched against
    # nothing. If the fragments below ever drifted to shapes that never nest
    # (or the rule started refusing every nested case), thousands of sources
    # could still repair with one brace each while not one alternative reading
    # was ever tried, and a guard on repairs would stay green over a search
    # that compared the rule against nothing.
    searched =
      for {source, fixed} <- repaired,
          rival <- rival_completions(source, byte_size(fixed) - byte_size(source)),
          do: {source, fixed, rival}

    assert length(searched) > 500,
           "the rule committed on #{length(repaired)} of #{length(sources)} sources, but only " <>
             "#{length(searched)} rival completions were parsed against those repairs — " <>
             "the search is too close to vacuous to prove anything"

    rivals =
      for {source, fixed, rival} <- searched,
          valid_syntax?(rival),
          do:
            "=== source ===\n#{source}=== rule emitted ===\n#{fixed}=== also parses ===\n#{rival}"

    assert rivals == [], Enum.join(rivals, "\n")
  end

  # Lines that open, continue or close a literal, in the shapes the rule's
  # guards talk about: nested openings, keyword and map entries, a leading
  # comma, an operator continuation, a closing brace mid-line, and a trailing
  # comment or string that would swallow an appended `}`.
  #
  # Only a source the rule *repairs* with two or more braces has a rival to
  # search, so every guard that makes the rule refuse also shrinks what this
  # test looks at. `{:ok, %{k: 1` is here to keep that population well clear of
  # the vacuity floor above: it is a two-brace opening with no rival placement
  # of its own, and it was added when the within-the-line guard took the count
  # from 621 to 456.
  defp brace_fragments do
    [
      "{1",
      "{1, {2",
      "{1, {2, {3",
      "%{a: {2",
      "%{a: 1",
      "%U{a: 1",
      "%{a: %{b: 2",
      ", {3",
      ", 4",
      ", %{b: 5",
      ", b: 5",
      ", [1",
      ", fn -> 1 end",
      "|> g()",
      "}, 5",
      "}, {6",
      "} ++ [1]",
      "} = y",
      "+ 1",
      "5",
      "b: 6",
      "{:ok, %{k: 1",
      "{}",
      "# c",
      "\"s\" <> t",
      "x",
      "3 => 4"
    ]
  end

  # The three body lines of a source built by `brace_fragments/0`, as indices.
  @body_lines 2..4//1

  # Every completion of `source` that appends `count` closing braces spread over
  # at least two body lines — the candidate rivals of the rule's single-line
  # repair. The caller parses them: the ones that parse are rival *meanings*,
  # and the ones that do not still count as search actually performed.
  defp rival_completions(source, count) do
    lines = String.split(source, "\n")

    for split <- brace_splits(count, Enum.count(@body_lines)),
        do: append_braces(lines, split)
  end

  defp brace_splits(count, line_count) do
    for(_ <- 1..line_count, do: 0..count)
    |> Enum.reduce([[]], fn range, splits ->
      for split <- splits, taken <- range, do: split ++ [taken]
    end)
    |> Enum.filter(&(Enum.sum(&1) == count and Enum.count(&1, fn taken -> taken > 0 end) >= 2))
  end

  defp append_braces(lines, split) do
    split
    |> Enum.zip(@body_lines)
    |> Enum.reduce(lines, fn {taken, index}, acc ->
      List.update_at(acc, index, &(&1 <> String.duplicate("}", taken)))
    end)
    |> Enum.join("\n")
  end

  test "scans a long literal without a blow-up in reparses" do
    # The uniqueness scan tries the missing braces on every earlier line of the
    # literal, and each try reparses the whole file. Trying every *count* on
    # every line made that 25 whole-file reparses per line. Only the shares of
    # the braces the repair actually needed can compete, so the bound is two
    # reparses per probed line: 401 lines for this fixture — the 400 key lines
    # plus `    x = %{` — i.e. 802 reparses, which is what tracing the parser
    # through one `fix/1` call on it counts. Nothing stops the scan earlier:
    # a probe that parses IS a competing placement and would make the rule
    # refuse, and the refusal is ruled out by `assert fix(code) != code` below.
    #
    # 400 entries, each spread over two lines. That is what gives the scan
    # anything to do: `sole_placement` skips every line ending in `,`, so the
    # 400 *key* lines (`      k1:`) are the only ones it probes. One line per
    # entry would end every earlier line in `,`, the scan would reparse nothing,
    # and the measurement below would time an empty loop.
    entries =
      Enum.map_join(1..400, "\n", fn i ->
        "      k#{i}:\n        #{i}#{if i < 400, do: ",", else: ""}"
      end)

    code = "defmodule Example do\n  def foo do\n    x = %{\n" <> entries <> "\n  end\nend\n"

    {keys, values} = entries |> String.split("\n") |> Enum.split_with(&String.ends_with?(&1, ":"))

    assert length(keys) == 400, "the scan probes the key lines — there must be 400 of them"

    assert Enum.count(values, &String.ends_with?(&1, ",")) == 399,
           "every value line but the last must end in `,`, so the scan skips it"

    # The budget is counted in control loops, not in milliseconds, so it means
    # the same thing on a slow CI box as on a fast laptop: `control` times 400
    # whole-file reparses of this fixture, and the scan is allowed six of those.
    # One probe is *cheaper* than one control reparse — the probe's `}` sits on
    # an earlier line, so the parser fails there and never reads the rest of the
    # file (0.17 of a whole-file parse on the first key line, 1.4 on the last) —
    # so the 802 probes measure about one control loop rather than two (0.9-1.7
    # across runs on one machine, the spread coming from which of the two loops
    # is timed first). The every-count scan replayed over the same fixture
    # measures 20.
    #
    # Second, smaller reason, for anyone re-tuning the 6: the two sides do not
    # use the same parser. The scan reparses with `Code.string_to_quoted`, while
    # `control` goes through `valid_syntax?/1`, which is a Sourceror parse —
    # rule tests may not reference `Code.*` themselves (see
    # test/no_parser_calls_in_rule_tests_test.exs), so a control loop is
    # "400 Sourceror parses", not "400 of the scan's reparses". On THIS fixture
    # that gap is small: measured min-of-11 over 100 parses each, Sourceror
    # costs 1.05-1.2x the plain parse, because the source fails at the `end` and
    # Sourceror never reaches its comment merging or literal encoder. With the
    # same file's map closed so it parses, Sourceror costs 5.0x. So the
    # unparseable fixture is what keeps the two comparable, and the ~1.2x it
    # still contributes sits inside the 0.9-1.7 run-to-run spread above. Both
    # facts are why 6 is a coarse fence between 1 and 20 rather than a tight
    # bound: pulled towards 2 it would start tracking Sourceror's overhead, and
    # a dependency bump would move it with nothing in the rule changing.
    best = Enum.min(for _ <- 1..3, do: elem(:timer.tc(fn -> fix(code) end), 0))

    control =
      Enum.min(
        for _ <- 1..3 do
          elem(:timer.tc(fn -> Enum.each(1..400, fn _ -> valid_syntax?(code) end) end), 0)
        end
      )

    assert fix(code) != code

    assert best < 6 * control,
           "the scan's 802 reparses cost #{Float.round(best / control, 2)} control loops " <>
             "(a loop is 400 whole-file reparses of this fixture); a healthy scan measures " <>
             "about 1, the every-count scan measures 20"
  end

  test "leaves a dangling comma untouched" do
    code = """
    defmodule Example do
      def foo do
        {:ok,
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves two unclosed literals untouched" do
    code = """
    defmodule Example do
      def foo do
        {:ok, 1
      end

      def bar do
        %{a: 1
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves a same-line mismatched end untouched" do
    code = """
    defmodule Example do
      def foo do x = {1, 2 end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves a brace hidden in a trailing comment untouched" do
    code = """
    defmodule Example do
      def foo do
        x = {1, 2 # oops
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "closes a nesting at the brace cap — five closing braces" do
    # The positive half of the `@max_braces` boundary, and what keeps the
    # refusal below from passing for the wrong reason: five closers is the
    # deepest repair the rule makes, and it makes it.
    input = """
    defmodule Example do
      def foo do
        {:ok, %{a: %{b: %{c: %{d: 1
      end
    end
    """

    expected = """
    defmodule Example do
      def foo do
        {:ok, %{a: %{b: %{c: %{d: 1}}}}}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "leaves a nesting past the brace cap untouched — six would be needed" do
    # One opening deeper than the case above: `@max_braces` caps the repair at
    # five, so a literal needing six closers is a degenerate input the rule
    # refuses like the shapes above rather than stacking ever more `}` onto one
    # line. The analyze side pins the same boundary; this pins that `fix/1`
    # hands the source back unedited (final newline aside — see the last test
    # in this file).
    code = """
    defmodule Example do
      def foo do
        {:ok, %{a: %{b: %{c: %{d: %{e: 1
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves an unrelated syntax error untouched" do
    code = """
    defmodule Example do
      def foo do
        x = [1, 2
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "keeps the source's final newline exactly as it found it" do
    # Every other assertion in this file goes through `confirm_fix/2`, which
    # compares with trailing newlines trimmed off both sides by design (see
    # test/support/rule_case.ex) — so nothing above actually pins the
    # "byte-for-byte" the comments claim. Measured, not assumed: with `fix/1`
    # wrapped in `String.trim_trailing(_, "\n")`, all eleven "left untouched"
    # cases and both brace-cap cases stay green; with a `"\n"` appended to
    # every repair, the positive cases stay green too. The only test that goes
    # red under either regression is the brace-split search, and it goes red
    # for the wrong reason — it compares `byte_size(fixed) - byte_size(source)`
    # to decide how many closers a repair added, so a stray newline makes it
    # accuse the rule of committing an ambiguous placement.
    #
    # The comparisons below are raw `==` on the bytes, in both directions: a
    # source that ends in a newline gets exactly one back, and a source that
    # does not stays without one.
    #
    # They compare *tuples* of results rather than one string per `assert`
    # because `Credence.FixtureHealer` (test/test_helper.exs runs it before the
    # suite compiles) rewrites any `assert <fix call> == expected` in this
    # directory into `confirm_fix(<fix call>, expected)` — on disk, silently.
    # A plain `assert fix(input) == expected` here therefore un-pins itself on
    # the next `mix test`; the healer only recognises a fix call sitting
    # directly on one side of the `==`, so wrapping the two sides in a tuple
    # keeps the byte comparison the healer would otherwise remove. (Verified:
    # this file comes back byte-identical from `mix test` in this shape.)
    input = """
    defmodule Example do
      def foo do
        {:ok, 1
      end
    end
    """

    expected = """
    defmodule Example do
      def foo do
        {:ok, 1}
      end
    end
    """

    refused = """
    defmodule Example do
      def foo do
        {:ok,
      end
    end
    """

    assert {fix(input), fix(refused)} == {expected, refused}

    bare_input = String.trim_trailing(input, "\n")
    bare_expected = String.trim_trailing(expected, "\n")
    bare_refused = String.trim_trailing(refused, "\n")

    assert {fix(bare_input), fix(bare_refused)} == {bare_expected, bare_refused}
  end
end
