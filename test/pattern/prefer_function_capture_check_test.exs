defmodule Credence.Pattern.PreferFunctionCaptureCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferFunctionCapture

  test "flags fn with single arg delegating to remote function call" do
    assert flagged?(PreferFunctionCapture, "fn sublist -> Enum.min(sublist) end")
  end

  test "flags fn with single arg delegating to local function call" do
    assert flagged?(PreferFunctionCapture, "fn x -> to_string(x) end")
  end

  test "flags fn in a pipe expression" do
    assert flagged?(PreferFunctionCapture, "list |> Enum.map(fn x -> String.upcase(x) end)")
  end

  test "flags fn with single arg delegating to Kernel function" do
    assert flagged?(PreferFunctionCapture, "fn x -> length(x) end")
  end

  test "leaves multi-arg fn alone" do
    assert clean?(PreferFunctionCapture, "fn x, y -> Enum.map(x, y) end")
  end

  test "leaves fn with complex body alone" do
    assert clean?(PreferFunctionCapture, "fn x -> x + 1 end")
  end

  test "leaves fn where param used more than once alone" do
    assert clean?(PreferFunctionCapture, "fn x -> Enum.map(x, x) end")
  end

  test "leaves fn with extra arguments alone" do
    assert clean?(PreferFunctionCapture, "fn x -> Enum.map(x, &(&1 + 1)) end")
  end

  test "leaves fn with no arguments alone" do
    assert clean?(PreferFunctionCapture, "fn -> :ok end")
  end

  test "leaves regular function calls alone" do
    assert clean?(PreferFunctionCapture, "Enum.min(list)")
  end

  test "leaves already captured function alone" do
    assert clean?(PreferFunctionCapture, "&Enum.min/1")
  end
end
