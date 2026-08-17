defmodule Credence.Syntax.NoAtomAsFunctionNameFixTest do
  use ExUnit.Case, async: true

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoAtomAsFunctionName

  defp analyze(code), do: NoAtomAsFunctionName.analyze(code)
  defp fix(code), do: NoAtomAsFunctionName.fix(code)

  describe "drops the leading colon" do
    test "the field sample" do
      input = """
      defmodule TableName do
        def table(name), do: :ets_table_name(name)
      end
      """

      expected = """
      defmodule TableName do
        def table(name), do: ets_table_name(name)
      end
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
      assert analyze(fix(input)) == []
    end

    # The colon that must survive. `:ets.whereis` is a real Erlang remote call; only
    # the inner local name is wrong. Nothing in the rule knows that `ets` is a real
    # module — the parser stopping at the inner `(` is what distinguishes them.
    test "repairs the inner call and leaves the Erlang remote call alone" do
      input = """
      defmodule TableName do
        def whereis(name), do: :ets.whereis(:ets_table_name(name))
      end
      """

      expected = """
      defmodule TableName do
        def whereis(name), do: :ets.whereis(ets_table_name(name))
      end
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "an atom ending in a question mark" do
      confirm_fix(fix("x = :valid?(1)"), "x = valid?(1)")
      assert valid_syntax?(fix("x = :valid?(1)"))
    end

    test "an atom ending in a bang" do
      confirm_fix(fix("x = :save!(1)"), "x = save!(1)")
    end

    test "leaves every other line byte-identical" do
      input = """
      defmodule Wide do
        @moduledoc "unchanged"
        def a(x), do: x
        def b(name), do: :tbl(name)
        def c(x), do: x
      end
      """

      expected = """
      defmodule Wide do
        @moduledoc "unchanged"
        def a(x), do: x
        def b(name), do: tbl(name)
        def c(x), do: x
      end
      """

      confirm_fix(fix(input), expected)
    end
  end

  # Every occurrence in ONE call, and this is not a preference. The Syntax round is a
  # single `Enum.reduce` over the rules — `fix/1` is called exactly once — and
  # `commit_or_roll_back/4` then throws away the whole round if the result still does
  # not parse. A rule that fixed one colon per call would therefore repair NOTHING on
  # a file with two. Measured before this loop existed: the round returned
  # `{NoAtomAsFunctionName, :rolled_back}` and the file byte-identical.
  describe "repairs every occurrence in one call" do
    test "two on one line" do
      once = fix("x = :a(1) + :b(2)")

      confirm_fix(once, "x = a(1) + b(2)")
      assert valid_syntax?(once)
      assert analyze(once) == []
    end

    test "two in one module" do
      input = """
      defmodule Two do
        def f(n), do: :tbl(n)
        def g(n), do: :other(n)
      end
      """

      expected = """
      defmodule Two do
        def f(n), do: tbl(n)
        def g(n), do: other(n)
      end
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    # `analyze/1` and `fix/1` share one loop, so the issue count is the repair count
    # rather than an independent guess at it.
    test "analyze reports one issue per repair" do
      input = """
      defmodule Three do
        def f(n), do: :a(n)
        def g(n), do: :b(n)
        def h(n), do: :c(n)
      end
      """

      assert length(analyze(input)) == 3
      assert valid_syntax?(fix(input))
      assert analyze(fix(input)) == []
    end

    # The round-level consequence, end to end.
    test "the whole round commits instead of rolling back" do
      input = """
      defmodule Two do
        def f(n), do: :tbl(n)
        def g(n), do: :other(n)
      end
      """

      {code, applied} = Credence.Syntax.fix_with_trace(input)

      assert applied == [{Credence.Syntax.NoAtomAsFunctionName, 1}]
      assert valid_syntax?(code)
      refute code == input
    end
  end

  describe "declines, byte for byte" do
    test "source that parses" do
      input = "x = :ets.new(:t, [])"
      confirm_fix(fix(input), input)
    end

    test "a decoy inside a string, with an unrelated parse error elsewhere" do
      input = """
      x = \"see :helper(1)\"
      y = (
      """

      confirm_fix(fix(input), input)
    end

    test "an unbalanced paren with no atom before it" do
      input = "x = foo((1"
      confirm_fix(fix(input), input)
    end

    test "a quoted atom" do
      input = ~S'x = :"my fun"(1)'
      confirm_fix(fix(input), input)
    end

    test "an operator atom" do
      input = "x = :+(1, 2)"
      confirm_fix(fix(input), input)
    end
  end

  # The self-corruption oracle's question, asked directly. A rule keyed on a parse
  # ERROR is structurally immune to the byte-scope class that the oracle exists to
  # catch: it cannot touch a file that parses, and every source file in the tree
  # parses. Measured over all of `lib/**/*.ex`: zero files altered.
  describe "cannot corrupt source that parses" do
    test "its own source is untouched" do
      own = File.read!("lib/syntax/no_atom_as_function_name.ex")

      confirm_fix(fix(own), own)
      assert analyze(own) == []
    end
  end
end
