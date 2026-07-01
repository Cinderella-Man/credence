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

  # Narrowing: only plain-identifier callees capture. Special-form
  # constructors and uncapturable identifier forms must be left alone —
  # `&{}/1`, `&<<>>/1`, `&var!/1` are compile errors, so rewriting them
  # would turn working code into code that no longer compiles.
  test "leaves tuple-constructor body alone" do
    assert clean?(PreferFunctionCapture, "fn x -> {x} end")
  end

  test "leaves bitstring-constructor body alone" do
    assert clean?(PreferFunctionCapture, "fn x -> <<x>> end")
  end

  test "leaves map-constructor body alone" do
    assert clean?(PreferFunctionCapture, "fn x -> %{a: x} end")
  end

  test "leaves var!/1 special form alone" do
    assert clean?(PreferFunctionCapture, "fn x -> var!(x) end")
  end

  # Rewriting an fn nested inside a `&` capture would produce an illegal nested
  # capture (`&Enum.map(&1, &to_string/1)`), so it must not be flagged.
  test "leaves an fn nested inside an enclosing & capture alone" do
    assert clean?(
             PreferFunctionCapture,
             "Enum.map(rows, &Enum.map(&1, fn v -> to_string(v) end))"
           )
  end

  test "still flags a top-level fn even when the file also has a capture-nested one" do
    code = """
    Enum.map(list, fn x -> String.upcase(x) end)
    Enum.map(rows, &Enum.map(&1, fn v -> to_string(v) end))
    """

    assert [_one] = check(PreferFunctionCapture, code)
  end
end
