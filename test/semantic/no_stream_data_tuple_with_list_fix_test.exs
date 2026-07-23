defmodule Credence.Semantic.NoStreamDataTupleWithListFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1, compiles?: 1]

  alias Credence.Semantic.NoStreamDataTupleWithList

  # The head of the real type-checker warning; the rule keys on the first line.
  @message """
  incompatible types given to StreamData.tuple/1:

      StreamData.tuple([key_gen, value_gen])

  given types:

      -dynamic(non_empty_list(%StreamData{generator: (none(), none() -> term())}))-

  but expected one of:

      {...}
  """

  defp fix(source, position) do
    NoStreamDataTupleWithList.fix(source, %{
      severity: :warning,
      message: @message,
      position: position
    })
  end

  test "swaps the brackets of the flagged list argument" do
    input = """
    defmodule CredenceTupleWithListFlagshipFix do
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

    expected = """
    defmodule CredenceTupleWithListFlagshipFix do
      @moduledoc false

      def object do
        key_gen = StreamData.string(:alphanumeric, min_length: 1, max_length: 8)
        value_gen = StreamData.integer()

        StreamData.list_of(
          StreamData.tuple({key_gen, value_gen}),
          max_length: 5
        )
        |> StreamData.map(&Map.new/1)
      end
    end
    """

    confirm_fix(fix(input, {9, 18}), expected)
    assert valid_syntax?(fix(input, {9, 18}))
    assert compiles?(fix(input, {9, 18}))
  end

  test "the whole semantic phase repairs the flagged call end to end" do
    input = """
    defmodule CredenceTupleWithListEndToEndFix do
      def object do
        StreamData.list_of(StreamData.tuple([StreamData.integer(), StreamData.boolean()]))
      end
    end
    """

    expected = """
    defmodule CredenceTupleWithListEndToEndFix do
      def object do
        StreamData.list_of(StreamData.tuple({StreamData.integer(), StreamData.boolean()}))
      end
    end
    """

    fixed = Credence.Semantic.fix(input)
    confirm_fix(fixed, expected)

    # The diagnostic the rule claimed is gone from the repaired source.
    assert Credence.Semantic.analyze(fixed) == []
  end

  test "swaps the brackets of an imported tuple/1 call" do
    input = """
    defmodule CredenceTupleWithListImportedFix do
      import StreamData

      def pair do
        tuple([integer(), boolean()])
      end
    end
    """

    expected = """
    defmodule CredenceTupleWithListImportedFix do
      import StreamData

      def pair do
        tuple({integer(), boolean()})
      end
    end
    """

    confirm_fix(fix(input, {5, 5}), expected)
  end

  test "keeps a multi-line argument, its comment and its indentation" do
    input = """
    defmodule CredenceTupleWithListThreeFix do
      def triple do
        StreamData.tuple([
          # the id
          StreamData.integer(),
          StreamData.boolean(),
          StreamData.binary()
        ])
      end
    end
    """

    expected = """
    defmodule CredenceTupleWithListThreeFix do
      def triple do
        StreamData.tuple({
          # the id
          StreamData.integer(),
          StreamData.boolean(),
          StreamData.binary()
        })
      end
    end
    """

    confirm_fix(fix(input, {3, 16}), expected)
  end

  test "swaps a one-element list into a one-element tuple" do
    input = """
    defmodule CredenceTupleWithListSingleFix do
      def one, do: StreamData.tuple([StreamData.integer()])
    end
    """

    expected = """
    defmodule CredenceTupleWithListSingleFix do
      def one, do: StreamData.tuple({StreamData.integer()})
    end
    """

    confirm_fix(fix(input, {2, 27}), expected)
  end

  test "swaps an empty list into an empty tuple" do
    input = """
    defmodule CredenceTupleWithListEmptyFix do
      def none, do: StreamData.tuple([])
    end
    """

    expected = """
    defmodule CredenceTupleWithListEmptyFix do
      def none, do: StreamData.tuple({})
    end
    """

    confirm_fix(fix(input, {2, 28}), expected)
  end

  test "rewrites only the call at the flagged position" do
    input = """
    defmodule CredenceTupleWithListTwoFix do
      def both do
        {StreamData.tuple([StreamData.integer()]), StreamData.tuple([StreamData.boolean()])}
      end
    end
    """

    expected = """
    defmodule CredenceTupleWithListTwoFix do
      def both do
        {StreamData.tuple({StreamData.integer()}), StreamData.tuple([StreamData.boolean()])}
      end
    end
    """

    confirm_fix(fix(input, {3, 17}), expected)

    # The compiler flags one call per pass, so a second pass finishes the file.
    both_fixed = """
    defmodule CredenceTupleWithListTwoFix do
      def both do
        {StreamData.tuple({StreamData.integer()}), StreamData.tuple({StreamData.boolean()})}
      end
    end
    """

    confirm_fix(input |> Credence.Semantic.fix() |> Credence.Semantic.fix(), both_fixed)
  end

  test "a line-only position is enough when the line holds one candidate" do
    input = """
    defmodule CredenceTupleWithListLineOnlyFix do
      def pair, do: StreamData.tuple([StreamData.integer(), StreamData.boolean()])
    end
    """

    expected = """
    defmodule CredenceTupleWithListLineOnlyFix do
      def pair, do: StreamData.tuple({StreamData.integer(), StreamData.boolean()})
    end
    """

    confirm_fix(fix(input, 2), expected)
  end

  test "a line-only position with two candidates on the line is left alone" do
    input = """
    defmodule CredenceTupleWithListLineOnlyTwoFix do
      def both do
        {StreamData.tuple([StreamData.integer()]), StreamData.tuple([StreamData.boolean()])}
      end
    end
    """

    confirm_fix(fix(input, 3), input)
  end

  #
  # No-ops — the cases the rule declines. Each source really is flagged by the
  # compiler with the message above; the fix has no safe rewrite for it.

  test "leaves a keyword-list argument alone" do
    input = """
    defmodule CredenceTupleWithListKeywordFix do
      def kw, do: StreamData.tuple(id: StreamData.integer())
    end
    """

    confirm_fix(fix(input, {2, 26}), input)
  end

  test "leaves a bracketed keyword-list argument alone" do
    input = """
    defmodule CredenceTupleWithListKeywordBracketsFix do
      def kw, do: StreamData.tuple([id: StreamData.integer()])
    end
    """

    confirm_fix(fix(input, {2, 26}), input)
  end

  test "leaves a cons cell alone" do
    input = """
    defmodule CredenceTupleWithListConsFix do
      def cons(rest), do: StreamData.tuple([StreamData.integer() | rest])
    end
    """

    confirm_fix(fix(input, {2, 34}), input)
  end

  test "leaves a list behind a variable alone" do
    input = """
    defmodule CredenceTupleWithListVariableFix do
      def gens do
        gens = [StreamData.integer(), StreamData.boolean()]
        StreamData.tuple(gens)
      end
    end
    """

    confirm_fix(fix(input, {4, 16}), input)
  end

  test "leaves a concatenated list alone" do
    input = """
    defmodule CredenceTupleWithListConcatFix do
      def gens(rest), do: StreamData.tuple([StreamData.integer()] ++ rest)
    end
    """

    confirm_fix(fix(input, {2, 30}), input)
  end

  test "leaves a non-list argument alone" do
    input = """
    defmodule CredenceTupleWithListAtomFix do
      def nope, do: StreamData.tuple(:foo)
    end
    """

    confirm_fix(fix(input, {2, 28}), input)
  end

  test "leaves a charlist argument alone" do
    input = """
    defmodule CredenceTupleWithListCharlistFix do
      def chars, do: StreamData.tuple(~c"ab")
    end
    """

    confirm_fix(fix(input, {2, 29}), input)
  end

  test "leaves an already-correct tuple argument alone" do
    input = """
    defmodule CredenceTupleWithListAlreadyTupleFix do
      def gen do
        StreamData.tuple({StreamData.integer(), StreamData.string(:alphanumeric)})
      end
    end
    """

    confirm_fix(fix(input, {3, 16}), input)
  end

  test "leaves a same-named local tuple/1 call at another position alone" do
    input = """
    defmodule CredenceTupleWithListLocalFix do
      defp tuple(list), do: List.to_tuple(list)

      def gen, do: tuple([1, 2])
    end
    """

    confirm_fix(fix(input, {9, 18}), input)
  end

  test "leaves a file with no tuple call alone" do
    input = """
    defmodule CredenceTupleWithListCleanFix do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, {2, 18}), input)
  end

  test "leaves unparseable source alone" do
    input = """
    defmodule CredenceTupleWithListBrokenFix do
      def gen, do: StreamData.tuple([
    end
    """

    confirm_fix(fix(input, {2, 27}), input)
  end

  test "leaves the source alone when the diagnostic carries no position" do
    input = """
    defmodule CredenceTupleWithListNoPositionFix do
      def pair, do: StreamData.tuple([StreamData.integer(), StreamData.boolean()])
    end
    """

    confirm_fix(fix(input, nil), input)
  end
end
