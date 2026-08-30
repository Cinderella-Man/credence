defmodule Credence.Pattern.NoUnusedComputationFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoUnusedComputation, as: Rule

  test "removes a dead length/1 on an inferred-list variable" do
    input = """
    def f(s) do
      chars = String.graphemes(s)
      _n = length(chars)
      Enum.with_index(chars)
    end
    """

    expected = """
    def f(s) do
      chars = String.graphemes(s)
      Enum.with_index(chars)
    end
    """

    confirm_fix(fix(Rule, input), expected)
  end

  test "removes a dead length/1 on a list literal" do
    input = """
    def f do
      _n = length([1, 2, 3])
      :ok
    end
    """

    expected = """
    def f do
      :ok
    end
    """

    confirm_fix(fix(Rule, input), expected)
  end

  test "keeps an underscore-prefixed binding that is read later" do
    input = """
    defmodule NoUnusedComputationUsedUnderscoreFixture do
      def f do
        _n = length([1])
        _n
      end
    end
    """

    emitted = fix(Rule, input)

    confirm_fix(emitted, input)
    assert {:ok, _diagnostics} = Credence.RuleHelpers.compile_and_capture(emitted)
  end

  test "leaves a bare-variable argument unchanged (unsafe)" do
    input = """
    def f(x) do
      _n = length(x)
      :ok
    end
    """

    confirm_fix(fix(Rule, input), input)
  end

  test "leaves a partial function unchanged" do
    input = """
    def f(a) do
      _n = div(a, 2)
      :ok
    end
    """

    confirm_fix(fix(Rule, input), input)
  end
end
