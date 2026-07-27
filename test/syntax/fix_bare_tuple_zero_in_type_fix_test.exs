defmodule Credence.Syntax.FixBareTupleZeroInTypeFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixBareTupleZeroInType

  defp analyze(code), do: FixBareTupleZeroInType.analyze(code)
  defp fix(code), do: FixBareTupleZeroInType.fix(code)

  test "fixes bare () in @type declaration" do
    input = """
    defmodule M do
      @type task_func :: () -> any()
    end
    """

    expected = """
    defmodule M do
      @type task_func :: (() -> any())
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes bare () with complex return type" do
    input = """
    defmodule M do
      @type handler :: () -> {:ok, term()} | {:error, term()}
    end
    """

    expected = """
    defmodule M do
      @type handler :: (() -> {:ok, term()} | {:error, term()})
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    code = """
    defmodule M do
      @type task_func :: () -> any()
    end
    """

    assert analyze(fix(code)) == []
  end

  test "fixed output is well-formed (parses)" do
    code = """
    defmodule M do
      @type task_func :: () -> any()
    end
    """

    assert valid_syntax?(fix(code))
  end

  test "does not modify already-correct code" do
    code = """
    defmodule M do
      @type task_func :: (() -> any())
    end
    """

    confirm_fix(fix(code), code)
  end

  test "does not modify non-function types" do
    code = """
    defmodule M do
      @type name :: atom()
      @type count :: integer()
    end
    """

    confirm_fix(fix(code), code)
  end

  test "ignores comment lines" do
    code = "# @type task_func :: () -> any()"
    confirm_fix(fix(code), code)
  end
end
