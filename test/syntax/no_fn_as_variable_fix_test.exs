defmodule Credence.Syntax.NoFnAsVariableFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoFnAsVariable

  defp analyze(code), do: NoFnAsVariable.analyze(code)
  defp fix(code), do: NoFnAsVariable.fix(code)

  describe "renames the `fn` identifier" do
    test "in a list pattern and in the body that references it" do
      input = """
      defmodule Fix do
        def foo([fn | rest]) do
          fn
        end
      end
      """

      expected = """
      defmodule Fix do
        def foo([func | rest]) do
          func
        end
      end
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
      assert analyze(fix(input)) == []
    end

    test "in a one-line head with a keyword `do:` body" do
      input = "def foo([fn | rest]), do: fn"

      expected = "def foo([func | rest]), do: func"

      confirm_fix(fix(input), expected)
    end

    test "in a tuple pattern" do
      input = """
      defmodule Fix do
        def foo({fn, x}) do
          fn
        end
      end
      """

      expected = """
      defmodule Fix do
        def foo({func, x}) do
          func
        end
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "when it is a bare value on the right of an assignment" do
      input = "x = fn"

      expected = "x = func"

      confirm_fix(fix(input), expected)
    end

    test "when it is the assignment target itself" do
      input = "fn = 1"

      expected = "func = 1"

      confirm_fix(fix(input), expected)
    end

    test "leaving the `:fn` atom and the `fn:` keyword key alone" do
      input = """
      defmodule Fix do
        def foo([fn | rest]) do
          %{fn: fn, kind: :fn, rest: rest}
        end
      end
      """

      expected = """
      defmodule Fix do
        def foo([func | rest]) do
          %{fn: func, kind: :fn, rest: rest}
        end
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "with multi-codepoint graphemes earlier on the line" do
      input = """
      defmodule Fix do
        def foo("👨‍👩‍👧" <> _, [fn | rest]), do: {fn, rest}
      end
      """

      expected = """
      defmodule Fix do
        def foo("👨‍👩‍👧" <> _, [func | rest]), do: {func, rest}
      end
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "in a later function too, once the file has shown `fn` is an identifier" do
      input = """
      defmodule Fix do
        def a([fn | rest]) do
          fn
        end

        def b(_x) do
          fn
        end
      end
      """

      expected = """
      defmodule Fix do
        def a([func | rest]) do
          func
        end

        def b(_x) do
          func
        end
      end
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "without touching a doc heredoc that also mentions `fn`" do
      input = """
      defmodule Fix do
        def go([fn | rest]) do
          fn
        end

        @doc \"\"\"
            fn
              x -> x
            end
        \"\"\"
        def other, do: :ok
      end
      """

      expected = """
      defmodule Fix do
        def go([func | rest]) do
          func
        end

        @doc \"\"\"
            fn
              x -> x
            end
        \"\"\"
        def other, do: :ok
      end
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end
  end

  describe "leaves the source byte-identical" do
    test "when it already parses" do
      code = """
      defmodule M do
        def go(list), do: Enum.map(list, fn x -> x + 1 end)
      end
      """

      confirm_fix(fix(code), code)
    end

    test "when the `fn` was closed by `)` — NoUnclosedFnDelimiter's case" do
      code = """
      defmodule M do
        def top(list), do: Enum.max_by(list, fn {_, second} -> second)
      end
      """

      confirm_fix(fix(code), code)
    end

    test "when the anonymous function is truncated" do
      code = """
      defmodule M do
        def go(list) do
          Enum.each(list, fn item ->
            IO.puts(item)
      """

      confirm_fix(fix(code), code)
    end

    test "when a standalone `fn` line has no positional evidence behind it" do
      code = """
      defmodule M do
        def go do
          fn
        end
      end
      """

      confirm_fix(fix(code), code)
    end

    test "when a multi-clause `fn` sits on its own line and a `do` block lost its `end`" do
      code = """
      defmodule M do
        def go(x) do
          handler =
            fn
              {:ok, v} -> v
              :error -> nil
            end

          handler.(x)
        end
      """

      confirm_fix(fix(code), code)
    end

    test "when the only standalone `fn` line lives inside a doc heredoc" do
      code = """
      defmodule M do
        @moduledoc \"\"\"
        Example:
            fn
            end
        \"\"\"
        def go([fn | rest]) do
          fn
        end
      end
      """

      confirm_fix(fix(code), code)
    end

    test "when `func` is already taken, so renaming would merge two variables" do
      code = """
      defmodule M do
        def foo(func, [fn | rest]) do
          {func, fn, rest}
        end
      end
      """

      confirm_fix(fix(code), code)
    end

    test "when the `fn` opens the body of a `case` clause" do
      code = """
      defmodule M do
        def go(x) do
          case x do
            1 ->
              fn
            2 -> :two
          end
        end
      end
      """

      confirm_fix(fix(code), code)
    end

    test "when the module is merely missing its final `end`" do
      code = """
      defmodule M do
        def go do
          :ok
        end
      """

      confirm_fix(fix(code), code)
    end
  end

  # ── T3.6 / escalation ledger row 164 ───────────────────────────────────
  #
  # Every fixture above this block is MODULE-LESS, and that is the whole gap:
  # wrap the moduledoc's own Bad example in a `defmodule` and the rule stopped
  # firing. After the first (pinned) rename the remaining `fn` sits mid-line, and
  # the parser blames the unterminated `defmodule do` — no column, and the line is
  # not "nothing but fn". Real code always has a module, which is why this
  # surfaced as an under-fire on a real row rather than in these tests.
  describe "inside a module, where real code lives" do
    test "the ledger's own source: a called `fn` variable" do
      input = """
      defmodule Row164 do
        defp try_fns([fn | rest], v), do: fn.(v) || try_fns(rest, v)
      end
      """

      expected = """
      defmodule Row164 do
        defp try_fns([func | rest], v), do: func.(v) || try_fns(rest, v)
      end
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "the moduledoc's Bad example, wrapped" do
      input = """
      defmodule Wrapped do
        def foo([fn | rest]), do: fn
      end
      """

      expected = """
      defmodule Wrapped do
        def foo([func | rest]), do: func
      end
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end
  end

  # The widening must not make the rule braver about real keywords. Each of
  # these parses, so the Syntax phase never runs on them in production — but the
  # matcher is what changed, so the matcher is what gets pinned.
  describe "CONTROL: genuine `fn` keywords are still untouched" do
    test "a multi-clause fn whose clauses start on the next line" do
      input = """
      defmodule Keyword1 do
        def run(xs) do
          Enum.map(xs, fn
            {:ok, v} -> v
            :error -> nil
          end)
        end
      end
      """

      confirm_fix(fix(input), input)
    end

    test "a dot inside an fn body is not a called `fn`" do
      input = """
      defmodule Keyword2 do
        def run(xs), do: Enum.map(xs, fn x -> x.field end)
      end
      """

      confirm_fix(fix(input), input)
    end

    test "an fn trailing a line whose next line opens clauses" do
      input = """
      defmodule Keyword3 do
        def run(xs) do
          Enum.reduce(xs, %{}, fn
            x, acc -> Map.put(acc, x, 1)
          end)
        end
      end
      """

      confirm_fix(fix(input), input)
    end
  end
end
