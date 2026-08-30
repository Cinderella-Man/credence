defmodule Credence.Syntax.NoFnAsVariableAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoFnAsVariable

  defp analyze(code), do: NoFnAsVariable.analyze(code)

  describe "flags a parser-pinpointed `fn` identifier" do
    test "`fn` closed by `]` — a list pattern" do
      code = """
      defmodule Fix do
        def foo([fn | rest]) do
          fn
        end
      end
      """

      assert [%Issue{rule: :no_fn_as_variable, meta: %{line: 2}}] = analyze(code)
    end

    test "`fn` closed by `}` — a tuple pattern" do
      code = """
      defmodule Fix do
        def foo({fn, x}) do
          fn
        end
      end
      """

      assert [%Issue{rule: :no_fn_as_variable}] = analyze(code)
    end

    test "a bare `fn` with no closing delimiter at all" do
      code = "x = fn"

      assert [%Issue{rule: :no_fn_as_variable}] = analyze(code)
    end
  end

  describe "no issue" do
    test "code that parses" do
      assert analyze("def foo(x), do: x") == []
    end

    test "code that parses and uses `fn` as the keyword" do
      code = """
      defmodule M do
        def go(list), do: Enum.map(list, fn x -> x + 1 end)
      end
      """

      assert analyze(code) == []
    end

    test "an `fn` closed by `)` — owned by NoUnclosedFnDelimiter" do
      code = """
      defmodule M do
        def top(list), do: Enum.max_by(list, fn {_, second} -> second)
      end
      """

      assert analyze(code) == []
    end

    test "a truncated anonymous function" do
      code = """
      defmodule M do
        def go(list) do
          Enum.each(list, fn item ->
            IO.puts(item)
      """

      assert analyze(code) == []
    end

    test "a standalone `fn` line with no positional evidence anywhere in the file" do
      code = """
      defmodule M do
        def go do
          fn
        end
      end
      """

      assert analyze(code) == []
    end

    test "a multi-clause `fn` on its own line while a `do` block lost its `end`" do
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

      assert analyze(code) == []
    end

    test "a `@moduledoc` example whose lines look like a stray `fn`" do
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

      assert analyze(code) == []
    end

    test "the file already uses `func`, so renaming would merge two variables" do
      code = """
      defmodule M do
        def foo(func, [fn | rest]) do
          {func, fn, rest}
        end
      end
      """

      assert analyze(code) == []
    end

    test "a `case` clause whose `fn` opens the next clause's body" do
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

      assert analyze(code) == []
    end

    test "a module that is merely missing its final `end`" do
      code = """
      defmodule M do
        def go do
          :ok
        end
      """

      assert analyze(code) == []
    end
  end
end
