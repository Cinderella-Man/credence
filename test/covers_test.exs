defmodule Credence.CoversTest do
  # Not async: verdict/1 compiles the `Solution` module (module redefinition).
  use ExUnit.Case, async: false

  alias Mix.Tasks.Credence.Covers

  test "an incomplete (non-compiling) snippet is NOVEL — no false duplicate (tunex docs/10)" do
    # Isolates an `if n == 0` idiom but calls helpers it never defines, so it does
    # not compile. UndefinedFunction matches the compile errors WITHOUT changing
    # anything — that must NOT count as the idiom being covered.
    snippet = """
    defmodule Solution do
      def f(n) do
        if n == 0 do
          0.0
        else
          helper(n) + other(n)
        end
      end
    end
    """

    assert Covers.verdict(snippet) == "NOVEL"
  end

  test "a compiling snippet an existing rule rewrites is COVERED" do
    # Enum.sort |> Enum.reverse is a known Credence Pattern idiom (-> Enum.sort(:desc)).
    snippet = """
    defmodule Solution do
      def f(l), do: l |> Enum.sort() |> Enum.reverse()
    end
    """

    assert Covers.verdict(snippet) == "COVERED"
  end

  test "a clean, novel compiling snippet is NOVEL" do
    snippet = """
    defmodule Solution do
      def f(n), do: n + 1
    end
    """

    assert Covers.verdict(snippet) == "NOVEL"
  end
end
