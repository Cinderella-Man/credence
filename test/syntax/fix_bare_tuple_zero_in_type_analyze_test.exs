defmodule Credence.Syntax.FixBareTupleZeroInTypeAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixBareTupleZeroInType

  defp analyze(code), do: FixBareTupleZeroInType.analyze(code)

  test "flags bare () before -> in @type" do
    code = """
    defmodule M do
      @type task_func :: () -> any()
    end
    """

    assert [%Issue{rule: :fix_bare_tuple_zero_in_type, meta: %{line: 2}}] = analyze(code)
  end

  test "flags bare () with multi-arg return type" do
    code = """
    defmodule M do
      @type handler :: () -> {:ok, term()} | {:error, term()}
    end
    """

    assert [%Issue{rule: :fix_bare_tuple_zero_in_type}] = analyze(code)
  end

  test "leaves already-parenthesized (() -> ...) alone" do
    code = """
    defmodule M do
      @type task_func :: (() -> any())
    end
    """

    assert analyze(code) == []
  end

  test "leaves non-function types alone" do
    code = """
    defmodule M do
      @type name :: atom()
      @type count :: integer()
    end
    """

    assert analyze(code) == []
  end

  test "ignores comment lines" do
    code = "# @type task_func :: () -> any()"
    assert analyze(code) == []
  end
end
