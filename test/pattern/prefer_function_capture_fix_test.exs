defmodule Credence.Pattern.PreferFunctionCaptureFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferFunctionCapture

  test "rewrites remote function call" do
    input = """
    fn sublist -> Enum.min(sublist) end
    """

    expected = """
    &Enum.min/1
    """

    assert fix(PreferFunctionCapture, input) == expected
  end

  test "rewrites local function call" do
    input = """
    fn x -> to_string(x) end
    """

    expected = """
    &to_string/1
    """

    assert fix(PreferFunctionCapture, input) == expected
  end

  test "rewrites fn in pipe expression" do
    input = """
    list |> Enum.map(fn x -> String.upcase(x) end)
    """

    expected = """
    list |> Enum.map(&String.upcase/1)
    """

    assert fix(PreferFunctionCapture, input) == expected
  end

  test "rewrites Kernel function call" do
    input = """
    fn x -> length(x) end
    """

    expected = """
    &length/1
    """

    assert fix(PreferFunctionCapture, input) == expected
  end

  test "does not rewrite multi-arg fn" do
    input = """
    fn x, y -> Enum.map(x, y) end
    """

    assert fix(PreferFunctionCapture, input) == input
  end

  test "does not rewrite complex body" do
    input = """
    fn x -> x + 1 end
    """

    assert fix(PreferFunctionCapture, input) == input
  end

  test "does not rewrite param used more than once" do
    input = """
    fn x -> Enum.map(x, x) end
    """

    assert fix(PreferFunctionCapture, input) == input
  end

  test "does not rewrite fn with extra arguments" do
    input = """
    fn x -> Enum.map(x, &(&1 + 1)) end
    """

    assert fix(PreferFunctionCapture, input) == input
  end
end
