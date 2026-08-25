defmodule Credence.Syntax.FixInlineKeywordIfInWithClauseFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixInlineKeywordIfInWithClause

  defp analyze(code), do: FixInlineKeywordIfInWithClause.analyze(code)
  defp fix(code), do: FixInlineKeywordIfInWithClause.fix(code)

  describe "wraps the `if` in parentheses" do
    test "every offending binding of one `with`, in place" do
      code = """
      defmodule M do
        def run(list, opts) do
          with {:ok, items} <- parse(list),
               ref <- if item_ref(opts), do: item_ref(opts), else: nil,
               parent <- if parent_ref(opts), do: parent_ref(opts), else: nil do
            {:ok, items, ref, parent}
          else
            _ -> {:error, :invalid}
          end
        end
      end
      """

      expected = """
      defmodule M do
        def run(list, opts) do
          with {:ok, items} <- parse(list),
               ref <- (if item_ref(opts), do: item_ref(opts), else: nil),
               parent <- (if parent_ref(opts), do: parent_ref(opts), else: nil) do
            {:ok, items, ref, parent}
          else
            _ -> {:error, :invalid}
          end
        end
      end
      """

      confirm_fix(fix(code), expected)
      assert valid_syntax?(fix(code))
      assert analyze(fix(code)) == []
    end

    test "keeping a later clause that uses the bound variable after it" do
      code = """
      defmodule M do
        def run(a) do
          with ref <- if a, do: 1, else: 2,
               {:ok, v} <- fetch(ref) do
            v
          end
        end
      end
      """

      expected = """
      defmodule M do
        def run(a) do
          with ref <- (if a, do: 1, else: 2),
               {:ok, v} <- fetch(ref) do
            v
          end
        end
      end
      """

      confirm_fix(fix(code), expected)
      assert valid_syntax?(fix(code))
    end

    test "when the offending binding is the last one, before the block's do" do
      code = """
      defmodule M do
        def run(a) do
          with {:ok, v} <- fetch(a),
               ref <- if v, do: 1, else: 2 do
            ref
          end
        end
      end
      """

      expected = """
      defmodule M do
        def run(a) do
          with {:ok, v} <- fetch(a),
               ref <- (if v, do: 1, else: 2) do
            ref
          end
        end
      end
      """

      confirm_fix(fix(code), expected)
      assert valid_syntax?(fix(code))
    end

    test "an `if` with no else" do
      code = """
      defmodule M do
        def run(a) do
          with ref <- if a, do: 1,
               {:ok, v} <- fetch(a) do
            {ref, v}
          end
        end
      end
      """

      expected = """
      defmodule M do
        def run(a) do
          with ref <- (if a, do: 1),
               {:ok, v} <- fetch(a) do
            {ref, v}
          end
        end
      end
      """

      confirm_fix(fix(code), expected)
      assert valid_syntax?(fix(code))
    end

    test "a nested keyword `if` inside a branch" do
      code = """
      defmodule M do
        def run(a, b) do
          with ref <- if a, do: (if b, do: 1, else: 2), else: 3,
               z <- f(a) do
            {ref, z}
          end
        end
      end
      """

      expected = """
      defmodule M do
        def run(a, b) do
          with ref <- (if a, do: (if b, do: 1, else: 2), else: 3),
               z <- f(a) do
            {ref, z}
          end
        end
      end
      """

      confirm_fix(fix(code), expected)
      assert valid_syntax?(fix(code))
    end

    test "branches holding commas — inside strings and as char literals" do
      code = """
      defmodule M do
        def run(a) do
          with ref <- if a, do: "one, two", else: "three, four",
               sep <- if a, do: ?,, else: ?;,
               z <- f(a) do
            {ref, sep, z}
          end
        end
      end
      """

      expected = """
      defmodule M do
        def run(a) do
          with ref <- (if a, do: "one, two", else: "three, four"),
               sep <- (if a, do: ?,, else: ?;),
               z <- f(a) do
            {ref, sep, z}
          end
        end
      end
      """

      confirm_fix(fix(code), expected)
      assert valid_syntax?(fix(code))
    end

    test "a line carrying a precomposed accent, a ZWJ emoji and a flag" do
      code = """
      defmodule M do
        def run(a) do
          with ref <- if a, do: "🇫🇷é", else: "👨‍👩‍👧",
               z <- f(a) do
            {ref, z}
          end
        end
      end
      """

      expected = """
      defmodule M do
        def run(a) do
          with ref <- (if a, do: "🇫🇷é", else: "👨‍👩‍👧"),
               z <- f(a) do
            {ref, z}
          end
        end
      end
      """

      confirm_fix(fix(code), expected)
      assert valid_syntax?(fix(code))
    end

    test "in a `for` generator too" do
      code = """
      defmodule M do
        def run(xs) do
          for x <- if xs, do: xs, else: [],
              y <- [1] do
            {x, y}
          end
        end
      end
      """

      expected = """
      defmodule M do
        def run(xs) do
          for x <- (if xs, do: xs, else: []),
              y <- [1] do
            {x, y}
          end
        end
      end
      """

      confirm_fix(fix(code), expected)
      assert valid_syntax?(fix(code))
    end

    test "several `with` blocks in one module" do
      code = """
      defmodule M do
        def a(x) do
          with r <- if x, do: 1, else: 2,
               z <- f(x) do
            {r, z}
          end
        end

        def b(x) do
          with q <- f(x),
               r <- if x, do: 3, else: 4 do
            {q, r}
          end
        end
      end
      """

      expected = """
      defmodule M do
        def a(x) do
          with r <- (if x, do: 1, else: 2),
               z <- f(x) do
            {r, z}
          end
        end

        def b(x) do
          with q <- f(x),
               r <- (if x, do: 3, else: 4) do
            {q, r}
          end
        end
      end
      """

      confirm_fix(fix(code), expected)
      assert valid_syntax?(fix(code))
    end

    test "more than fifty offending bindings are all repaired" do
      bare_bindings =
        Enum.map_join(1..51, "\n", fn i ->
          "       value#{i} <- if flag, do: #{i}, else: 0,"
        end)

      wrapped_bindings =
        Enum.map_join(1..51, "\n", fn i ->
          "       value#{i} <- (if flag, do: #{i}, else: 0),"
        end)

      values = Enum.map_join(1..51, ", ", &"value#{&1}")

      code =
        "defmodule Credence.Syntax.FixInlineKeywordIfOverFiftyFixture do\n" <>
          "  def run(flag) do\n    with " <>
          bare_bindings <>
          "\n       done <- List.wrap(flag) do\n      {[" <>
          values <> "], done}\n    end\n  end\nend\n"

      expected =
        "defmodule Credence.Syntax.FixInlineKeywordIfOverFiftyFixture do\n" <>
          "  def run(flag) do\n    with " <>
          wrapped_bindings <>
          "\n       done <- List.wrap(flag) do\n      {[" <>
          values <> "], done}\n    end\n  end\nend\n"

      emitted = fix(code)

      confirm_fix(emitted, expected)
      assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(emitted)
      assert analyze(emitted) == []
      confirm_fix(fix(emitted), emitted)
    end

    test "is idempotent — a second pass changes nothing" do
      code = """
      defmodule M do
        def run(a) do
          with ref <- if a, do: 1, else: 2,
               z <- f(a) do
            {ref, z}
          end
        end
      end
      """

      once = fix(code)

      confirm_fix(fix(once), once)
    end
  end

  describe "leaves alone" do
    test "code that already parses" do
      code = """
      defmodule M do
        def run(a) do
          with {:ok, v} <- fetch(a) do
            ref = if v, do: 1, else: 2
            ref
          end
        end
      end
      """

      confirm_fix(fix(code), code)
    end

    test "the same parse errors with no `<-` binding" do
      code = "foo(1, key: 2, 3)"

      confirm_fix(fix(code), code)

      other = """
      foo bar 1, key: 2, other
      """

      confirm_fix(fix(other), other)
    end

    test "a keyword list that belongs to something other than `if`" do
      code = """
      defmodule M do
        def run(a) do
          with ref <- case(a), do: 1, else: 2,
               {:ok, v} <- fetch(a) do
            {ref, v}
          end
        end
      end
      """

      confirm_fix(fix(code), code)
    end

    test "an `if` continued on the line after the `<-`" do
      code = """
      defmodule M do
        def run(a) do
          with ref <-
                 if a, do: 1, else: 2,
               z <- f(a) do
            {ref, z}
          end
        end
      end
      """

      confirm_fix(fix(code), code)
    end

    test "a last binding with a trailing comment after `do`" do
      code = """
      defmodule M do
        def run(a) do
          with {:ok, v} <- fetch(a),
               ref <- if v, do: 1, else: 2 do # note
            ref
          end
        end
      end
      """

      confirm_fix(fix(code), code)
    end

    test "`if(cond), do:` — parentheses around the span would not repair it" do
      code = """
      defmodule M do
        def run(a) do
          with ref <- if(a), do: 1, else: 2,
               z <- f(a) do
            {ref, z}
          end
        end
      end
      """

      confirm_fix(fix(code), code)
    end

    test "an `if` whose branch quotes an arrow and an `if` of its own" do
      code = """
      defmodule M do
        def run(a) do
          with ref <- if a, do: "x <- if y, do: 1", else: nil,
               z <- f(a) do
            {ref, z}
          end
        end
      end
      """

      confirm_fix(fix(code), code)
    end

    test "the bad shape quoted inside a heredoc, with the real error elsewhere" do
      code = """
      defmodule M do
        @moduledoc \"\"\"
        Bad:

            with ref <- if a, do: 1, else: 2,
                 z <- f(a) do
              {ref, z}
            end
        \"\"\"

        def broken(x) do
          x +
        end
      end
      """

      confirm_fix(fix(code), code)
    end

    test "this rule's own source, whose docs show the bad shape, when it stops parsing" do
      code = File.read!("lib/syntax/fix_inline_keyword_if_in_with_clause.ex") <> "x +\n"

      confirm_fix(fix(code), code)
    end
  end
end
