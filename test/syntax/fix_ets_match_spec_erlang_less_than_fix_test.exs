defmodule Credence.Syntax.FixEtsMatchSpecErlangLessThanFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixEtsMatchSpecErlangLessThan

  defp analyze(code), do: FixEtsMatchSpecErlangLessThan.analyze(code)
  defp fix(code), do: FixEtsMatchSpecErlangLessThan.fix(code)

  test "fixes the bare atom in a match spec guard" do
    input = ~S"""
    guards = [{:=<, :"$1", cutoff}]
    """

    expected = ~S"""
    guards = [{:"=<", :"$1", cutoff}]
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes the bare atom inside a full :ets.select spec" do
    input = ~S"""
    :ets.select(table, [{{:"$1", :"$2"}, [{:=<, :"$2", 10}], [:"$1"]}])
    """

    expected = ~S"""
    :ets.select(table, [{{:"$1", :"$2"}, [{:"=<", :"$2", 10}], [:"$1"]}])
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes every occurrence in a module, leaving everything else byte-identical" do
    input = ~S"""
    defmodule Cache do
      def expired(cutoff) do
        :ets.select(:cache, [{{:"$1", :"$2"}, [{:=<, :"$2", cutoff}], [:"$1"]}])
      end

      def window(lo, hi) do
        [{:>=, :"$1", lo}, {:=<, :"$1", hi}]
      end
    end
    """

    expected = ~S"""
    defmodule Cache do
      def expired(cutoff) do
        :ets.select(:cache, [{{:"$1", :"$2"}, [{:"=<", :"$2", cutoff}], [:"$1"]}])
      end

      def window(lo, hi) do
        [{:>=, :"$1", lo}, {:"=<", :"$1", hi}]
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes two occurrences on one line" do
    input = ~S"""
    [{:=<, :"$1", a}, {:=<, :"$2", b}]
    """

    expected = ~S"""
    [{:"=<", :"$1", a}, {:"=<", :"$2", b}]
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes two adjacent occurrences with no space between them" do
    input = ~S"""
    ops = [:=<,:=<]
    """

    expected = ~S"""
    ops = [:"=<",:"=<"]
    """

    confirm_fix(fix(input), expected)
  end

  test "splices by byte offset without mangling multibyte text on the line" do
    input = ~S"""
    guards = [{:==, :"$1", "café"}, {:=<, :"$2", "naïve"}]
    """

    expected = ~S"""
    guards = [{:==, :"$1", "café"}, {:"=<", :"$2", "naïve"}]
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes a bare atom followed by a closing bracket" do
    input = ~S"""
    ops = [:=<]
    """

    expected = ~S"""
    ops = [:"=<"]
    """

    confirm_fix(fix(input), expected)
  end

  test "leaves the already-correct quoted atom alone" do
    code = ~S"""
    guards = [{:"=<", :"$1", cutoff}]
    """

    confirm_fix(fix(code), code)
  end

  # `:=` is a valid atom, so each shape below parses today as `:=` followed by a
  # comparison — rewriting it would turn working code into a syntax error.

  test "does not touch `:=< y` — that parses as `:= < y`" do
    code = ~S"""
    x = :=< y
    """

    confirm_fix(fix(code), code)
  end

  test "does not touch `:=<y` — that parses as `:= < y`" do
    code = ~S"""
    x = :=<y
    """

    confirm_fix(fix(code), code)
  end

  test "does not touch `:=<= y` — that parses as `:= <= y`" do
    code = ~S"""
    x = :=<= y
    """

    confirm_fix(fix(code), code)
  end

  test "does not touch `:=<>` — that parses as `:= <> \"a\"`" do
    code = ~S"""
    x = :=<>"a"
    """

    confirm_fix(fix(code), code)
  end

  test "does not touch a trailing :=< — the right operand may be on the next line" do
    code = ~S"""
    x = :=<
    """

    confirm_fix(fix(code), code)
  end

  test "does not touch :=< in a comment" do
    code = ~S"""
    # guards = [{:=<, :"$1", cutoff}]
    """

    confirm_fix(fix(code), code)
  end

  test "does not touch :=< inside a string" do
    code = ~S"""
    message = "use [{:=<, x}] here"
    """

    confirm_fix(fix(code), code)
  end

  test "does not touch :=< inside a heredoc body" do
    code = """
    defmodule M do
      @moduledoc \"\"\"
      Erlang match specs write it as [{:=<, :"$1", 5}].
      \"\"\"
    end
    """

    confirm_fix(fix(code), code)
  end

  test "fixes real code while leaving a documenting heredoc and comment untouched" do
    input = """
    defmodule Cache do
      @moduledoc \"\"\"
      Guards look like [{:=<, :"$1", cutoff}].
      \"\"\"

      # the guard tuple is [{:=<, :"$1", cutoff}]
      def expired(cutoff), do: [{:=<, :"$1", cutoff}]
    end
    """

    expected = """
    defmodule Cache do
      @moduledoc \"\"\"
      Guards look like [{:=<, :"$1", cutoff}].
      \"\"\"

      # the guard tuple is [{:=<, :"$1", cutoff}]
      def expired(cutoff), do: [{:"=<", :"$1", cutoff}]
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = ~S"""
    guards = [{:=<, :"$1", cutoff}]
    """

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    guards = [{:=<, :"$1", cutoff}]
    """

    assert valid_syntax?(fix(input))
  end

  test "fixed module output is well-formed (parses)" do
    input = ~S"""
    defmodule Cache do
      def expired(cutoff) do
        :ets.select(:cache, [{{:"$1", :"$2"}, [{:=<, :"$2", cutoff}], [:"$1"]}])
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "the shapes the rule skips are valid Elixir before and after the fix" do
    for code <- [
          ~S"""
          x = :=< y
          """,
          ~S"""
          x = :=<y
          """,
          ~S"""
          x = :=<= y
          """,
          ~S"""
          x = :=<>"a"
          """
        ] do
      assert valid_syntax?(code)
      assert valid_syntax?(fix(code))
    end
  end
end
