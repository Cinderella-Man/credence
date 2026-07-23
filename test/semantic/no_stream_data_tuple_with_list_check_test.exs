defmodule Credence.Semantic.NoStreamDataTupleWithListCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoStreamDataTupleWithList

  # Real diagnostic shape from `Code.with_diagnostics/1` compiling the flagship
  # input of the fix test — a type-checker warning whose column points at the
  # `tuple` token. The message is reproduced down to its "expected one of"
  # section; the typing traces that follow it are elided.
  @message """
  incompatible types given to StreamData.tuple/1:

      StreamData.tuple([key_gen, value_gen])

  given types:

      -dynamic(non_empty_list(%StreamData{generator: (none(), none() -> term())}))-

  but expected one of:

      {...}
  """

  @diag %{severity: :warning, message: @message, position: {9, 18}}

  @flagship """
  defmodule CredenceTupleWithListFlagshipCheck do
    @moduledoc false

    def object do
      key_gen = StreamData.string(:alphanumeric, min_length: 1, max_length: 8)
      value_gen = StreamData.integer()

      StreamData.list_of(
        StreamData.tuple([key_gen, value_gen]),
        max_length: 5
      )
      |> StreamData.map(&Map.new/1)
    end
  end
  """

  test "matches the incompatible-types diagnostic for StreamData.tuple/1" do
    assert NoStreamDataTupleWithList.match?(@diag)
  end

  test "the semantic phase dispatches this rule for the diagnostic" do
    winner =
      Credence.Semantic.Rule
      |> Credence.RuleHelpers.discover_rules()
      |> Enum.find(& &1.match?(@diag))

    assert winner == NoStreamDataTupleWithList
  end

  test "premise: StreamData.tuple/1 raises on a list and works on a tuple" do
    gens = [StreamData.integer(), StreamData.boolean()]

    # Through `apply/3` so this suite does not emit the very warning the rule
    # exists to clear.
    assert_raise FunctionClauseError, fn -> apply(StreamData, :tuple, [gens]) end

    assert [{int, bool}] =
             {StreamData.integer(), StreamData.boolean()}
             |> StreamData.tuple()
             |> Enum.take(1)

    assert is_integer(int)
    assert is_boolean(bool)

    # The degenerate arities the fix also produces are legal generators.
    assert Enum.take(StreamData.tuple({}), 1) == [{}]
    assert [{one}] = StreamData.tuple({StreamData.integer()}) |> Enum.take(1)
    assert is_integer(one)
  end

  test "ignores unrelated diagnostics" do
    refute NoStreamDataTupleWithList.match?(%{
             severity: :warning,
             message: "unrelated",
             position: {1, 1}
           })
  end

  test "ignores incompatible types given to a different function" do
    refute NoStreamDataTupleWithList.match?(%{
             severity: :warning,
             message: "incompatible types given to StreamData.integer/1:\n\n    StreamData.integer({1, 2})\n",
             position: {3, 16}
           })

    refute NoStreamDataTupleWithList.match?(%{
             severity: :warning,
             message: "incompatible types given to NaiveDateTime.new!/2:\n\n    NaiveDateTime.new!(d, {1, 2})\n",
             position: {3, 16}
           })
  end

  test "ignores a different arity of StreamData.tuple" do
    refute NoStreamDataTupleWithList.match?(%{
             severity: :warning,
             message: "incompatible types given to StreamData.tuple/2:\n\n    StreamData.tuple([a], [b])\n",
             position: {3, 16}
           })
  end

  test "ignores the generic compile error wrapper" do
    refute NoStreamDataTupleWithList.match?(%{
             severity: :error,
             message: "credence_check.ex: cannot compile module Foo (errors have been logged)",
             position: 0
           })
  end

  test "attributes the issue to this rule" do
    assert NoStreamDataTupleWithList.to_issue(@diag).rule == :no_stream_data_tuple_with_list
  end

  test "preserves the line in the issue" do
    assert NoStreamDataTupleWithList.to_issue(@diag).meta.line == 9

    bare = %{severity: :warning, message: @message, position: 42}
    assert NoStreamDataTupleWithList.to_issue(bare).meta.line == 42
  end

  test "reports the flagged call" do
    assert NoStreamDataTupleWithList.should_report?(@diag, @flagship)
  end

  test "the phase reports the issue for a real compile of the flagship" do
    issues = Credence.Semantic.analyze(@flagship)

    assert Enum.map(issues, & &1.rule) == [:no_stream_data_tuple_with_list]
    assert Enum.map(issues, & &1.meta.line) == [9]
  end

  test "the issue explains the repair" do
    assert NoStreamDataTupleWithList.to_issue(@diag).message ==
             "StreamData.tuple/1 expects a tuple of generators, not a list — use {gen1, gen2}"
  end

  #
  # No issue — the cases the fix deliberately declines to rewrite. Reporting
  # them would promise a repair that never arrives. Each source really is
  # flagged by the compiler; only this rule stays quiet.

  test "no issue for a keyword-list argument" do
    source = """
    defmodule CredenceTupleWithListKeywordCheck do
      def kw, do: StreamData.tuple(id: StreamData.integer())
    end
    """

    diag = %{severity: :warning, message: @message, position: {2, 26}}
    refute NoStreamDataTupleWithList.should_report?(diag, source)
    assert Credence.Semantic.analyze(source) == []
  end

  test "no issue for a bracketed keyword-list argument" do
    source = """
    defmodule CredenceTupleWithListKeywordBracketsCheck do
      def kw, do: StreamData.tuple([id: StreamData.integer()])
    end
    """

    diag = %{severity: :warning, message: @message, position: {2, 26}}
    refute NoStreamDataTupleWithList.should_report?(diag, source)
    assert Credence.Semantic.analyze(source) == []
  end

  test "no issue for a cons cell" do
    source = """
    defmodule CredenceTupleWithListConsCheck do
      def cons(rest), do: StreamData.tuple([StreamData.integer() | rest])
    end
    """

    diag = %{severity: :warning, message: @message, position: {2, 34}}
    refute NoStreamDataTupleWithList.should_report?(diag, source)
    assert Credence.Semantic.analyze(source) == []
  end

  test "no issue when the list is behind a variable" do
    source = """
    defmodule CredenceTupleWithListVariableCheck do
      def gens do
        gens = [StreamData.integer(), StreamData.boolean()]
        StreamData.tuple(gens)
      end
    end
    """

    diag = %{severity: :warning, message: @message, position: {4, 16}}
    refute NoStreamDataTupleWithList.should_report?(diag, source)
    assert Credence.Semantic.analyze(source) == []
  end

  test "no issue for a non-list argument" do
    source = """
    defmodule CredenceTupleWithListAtomCheck do
      def nope, do: StreamData.tuple(:foo)
    end
    """

    diag = %{severity: :warning, message: @message, position: {2, 28}}
    refute NoStreamDataTupleWithList.should_report?(diag, source)
    assert Credence.Semantic.analyze(source) == []
  end

  test "no issue for a charlist argument, which is a list with no brackets" do
    source = """
    defmodule CredenceTupleWithListCharlistCheck do
      def chars, do: StreamData.tuple(~c"ab")
    end
    """

    diag = %{severity: :warning, message: @message, position: {2, 29}}
    refute NoStreamDataTupleWithList.should_report?(diag, source)
    assert Credence.Semantic.analyze(source) == []
  end

  test "no issue when the flagged position holds no one-argument tuple call" do
    diag = %{severity: :warning, message: @message, position: {12, 5}}
    refute NoStreamDataTupleWithList.should_report?(diag, @flagship)
  end
end
