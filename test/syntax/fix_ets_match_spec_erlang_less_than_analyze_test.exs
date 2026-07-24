defmodule Credence.Syntax.FixEtsMatchSpecErlangLessThanAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixEtsMatchSpecErlangLessThan

  defp analyze(code), do: FixEtsMatchSpecErlangLessThan.analyze(code)

  test "flags a bare :=< in a match spec guard" do
    code = ~S"""
    guards = [{:=<, :"$1", cutoff}]
    """

    assert [
             %Issue{
               rule: :fix_ets_match_spec_erlang_less_than,
               message: message,
               meta: %{line: 1}
             }
           ] =
             analyze(code)

    assert message ==
             "Bare atom `:=<` is not valid Elixir. " <>
               "Use `:\"=<\"` for less-than-or-equal in ETS match specs."
  end

  test "flags a bare :=< inside a full :ets.select spec" do
    code = ~S"""
    :ets.select(table, [{{:"$1", :"$2"}, [{:=<, :"$2", 10}], [:"$1"]}])
    """

    assert [%Issue{meta: %{line: 1}}] = analyze(code)
  end

  test "flags every occurrence on the line, and reports the right lines" do
    code = ~S"""
    defmodule M do
      def spec do
        [{:=<, :"$1", a}, {:=<, :"$2", b}]
      end
    end
    """

    assert [%Issue{meta: %{line: 3}}, %Issue{meta: %{line: 3}}] = analyze(code)
  end

  test "leaves the already-correct quoted atom alone" do
    code = ~S"""
    guards = [{:"=<", :"$1", cutoff}]
    """

    assert analyze(code) == []
  end

  # `:=` is a valid atom, so each shape below parses today as `:=` followed by a
  # comparison. The rule refuses them (and so must never flag them).

  test "no issue for `:=< y` — that parses as `:= < y`" do
    code = ~S"""
    x = :=< y
    """

    assert analyze(code) == []
  end

  test "no issue for `:=<y` — that parses as `:= < y`" do
    code = ~S"""
    x = :=<y
    """

    assert analyze(code) == []
  end

  test "no issue for `:=<= y` — that parses as `:= <= y`" do
    code = ~S"""
    x = :=<= y
    """

    assert analyze(code) == []
  end

  test "no issue for `:=<>` — that parses as `:= <> \"a\"`" do
    code = ~S"""
    x = :=<>"a"
    """

    assert analyze(code) == []
  end

  test "no issue for a trailing :=< — the right operand may be on the next line" do
    code = ~S"""
    x = :=<
    """

    assert analyze(code) == []
  end

  test "no issue for :=< in a comment" do
    code = ~S"""
    # guards = [{:=<, :"$1", cutoff}]
    """

    assert analyze(code) == []
  end

  test "no issue for :=< inside a string" do
    code = ~S"""
    message = "use [{:=<, x}] here"
    """

    assert analyze(code) == []
  end

  test "no issue for :=< inside a heredoc body" do
    code = """
    defmodule M do
      @moduledoc \"\"\"
      Erlang match specs write it as [{:=<, :"$1", 5}].
      \"\"\"
    end
    """

    assert analyze(code) == []
  end
end
