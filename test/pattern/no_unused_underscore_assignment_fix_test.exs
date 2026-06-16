defmodule Credence.Pattern.NoUnusedUnderscoreAssignmentFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoUnusedUnderscoreAssignment, as: Rule

  test "removes the dead underscore assignment (bare-var RHS)" do
    input = """
    def process(list) do
      _length = list
      n = length(list)
      if n < 3, do: 0, else: n
    end
    """

    expected = """
    def process(list) do
      n = length(list)
      if n < 3, do: 0, else: n
    end
    """

    confirm_fix(fix(Rule, input), expected)
  end

  test "removes a literal-RHS dead assignment" do
    input = """
    def run(x) do
      _unused = 1
      x + 1
    end
    """

    expected = """
    def run(x) do
      x + 1
    end
    """

    confirm_fix(fix(Rule, input), expected)
  end

  test "removes multiple dead assignments in one block" do
    input = """
    def run(x) do
      _a = 1
      _b = :ok
      x
    end
    """

    expected = """
    def run(x) do
      x
    end
    """

    confirm_fix(fix(Rule, input), expected)
  end

  test "leaves a call-RHS assignment alone" do
    input = """
    def run(x) do
      _unused = IO.puts("hi")
      x
    end
    """

    confirm_fix(fix(Rule, input), input)
  end

  test "leaves a referenced underscore variable alone" do
    input = """
    def run(x) do
      _kept = x
      _kept + 1
    end
    """

    confirm_fix(fix(Rule, input), input)
  end

  test "leaves a last-position assignment alone" do
    input = """
    def run(x) do
      x
      _unused = 0
    end
    """

    confirm_fix(fix(Rule, input), input)
  end
end
