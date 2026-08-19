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
end
