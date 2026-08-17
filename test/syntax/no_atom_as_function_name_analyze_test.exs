defmodule Credence.Syntax.NoAtomAsFunctionNameAnalyzeTest do
  use ExUnit.Case, async: true

  alias Credence.Issue
  alias Credence.Syntax.NoAtomAsFunctionName

  defp analyze(code), do: NoAtomAsFunctionName.analyze(code)

  describe "flags an atom in call position" do
    # Both fixtures are the field samples recorded in docs/18, from one generated
    # file: an Erlang module-colon carried onto a LOCAL function name.
    test "the field sample" do
      assert [%Issue{rule: :no_atom_as_function_name}] =
               analyze("""
               defmodule TableName do
                 def table(name), do: :ets_table_name(name)
               end
               """)
    end

    # The instructive one: `:ets.whereis` is CORRECT and the inner
    # `:ets_table_name` is not. The parser stops at the inner `(`, so keying on its
    # position picks the right colon without the rule having to know which module
    # names are real.
    test "a bad inner call inside a legitimate Erlang remote call" do
      assert [%Issue{rule: :no_atom_as_function_name}] =
               analyze("""
               defmodule TableName do
                 def whereis(name), do: :ets.whereis(:ets_table_name(name))
               end
               """)
    end

    test "an atom ending in a question mark" do
      assert analyze("x = :valid?(1)") != []
    end

    test "an atom ending in a bang" do
      assert analyze("x = :save!(1)") != []
    end
  end

  describe "declines" do
    # Source that parses can never be this defect, and `locate/1` requires a parse
    # ERROR — which is what makes the whole decoy class unreachable rather than
    # merely filtered.
    test "source that parses" do
      assert analyze("x = :ets.new(:t, [])") == []
    end

    # The rejected implementation scanned the whole source with `Regex.replace`, so
    # a `:word(` in a string or comment was indistinguishable from the real thing.
    # Here the file fails to parse for an UNRELATED reason, and the parser stops at
    # the stray `(` on line 2 — not at the decoy on line 1.
    test "a decoy inside a string, with an unrelated parse error elsewhere" do
      assert analyze("""
             x = \"see :helper(1)\"
             y = (
             """) == []
    end

    test "a decoy inside a comment, with an unrelated parse error elsewhere" do
      assert analyze("""
             # call :helper(1) like this
             y = (
             """) == []
    end

    test "an unbalanced paren with no atom before it" do
      assert analyze("x = foo((1") == []
    end

    # Same failure mode, but dropping the colon does not yield valid code — see the
    # moduledoc's executed table — so there is no one-character repair and the rule
    # declines rather than reporting something it will not fix.
    test "a quoted atom, which has no one-character repair" do
      assert analyze(~S'x = :"my fun"(1)') == []
    end

    test "an operator atom, which has no one-character repair" do
      assert analyze("x = :+(1, 2)") == []
    end
  end
end
