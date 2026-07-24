defmodule Credence.Syntax.FixCaptureOperatorSyntaxAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixCaptureOperatorSyntax

  defp analyze(code), do: FixCaptureOperatorSyntax.analyze(code)

  test "flags &>" do
    assert [%Issue{rule: :fix_capture_operator_syntax, message: message, meta: %{line: 1}}] =
             analyze(":gt -> &>")

    assert message ==
             "Capture syntax `&>` is not valid in Elixir. " <>
               "Use `&Kernel.>/2` for a function reference instead."
  end

  test "flags &<" do
    assert [%Issue{rule: :fix_capture_operator_syntax, message: message}] =
             analyze(":lt -> &<")

    assert message ==
             "Capture syntax `&<` is not valid in Elixir. " <>
               "Use `&Kernel.</2` for a function reference instead."
  end

  test "flags &>=" do
    assert [%Issue{rule: :fix_capture_operator_syntax, message: message}] =
             analyze(":gte -> &>=")

    assert message ==
             "Capture syntax `&>=` is not valid in Elixir. " <>
               "Use `&Kernel.>=/2` for a function reference instead."
  end

  test "flags &<=" do
    assert [%Issue{rule: :fix_capture_operator_syntax, message: message}] =
             analyze(":lte -> &<=")

    assert message ==
             "Capture syntax `&<=` is not valid in Elixir. " <>
               "Use `&Kernel.<=/2` for a function reference instead."
  end

  test "flags multiple capture operators in source" do
    source = """
    case op_name do
      :gt -> &>
      :lt -> &<
      :gte -> &>=
      :lte -> &<=
    end
    """

    assert [
             %Issue{meta: %{line: 2}},
             %Issue{meta: %{line: 3}},
             %Issue{meta: %{line: 4}},
             %Issue{meta: %{line: 5}}
           ] = analyze(source)
  end

  test "flags two capture operators on one line" do
    assert [%Issue{meta: %{line: 1}}, %Issue{meta: %{line: 1}}] = analyze("[&>, &<]")
  end

  test "flags a capture operator as the last argument of a call" do
    assert [%Issue{meta: %{line: 1}}] = analyze("Enum.sort(list, &>)")
  end

  test "leaves valid Kernel captures alone" do
    source = """
    case op_name do
      :gt -> &Kernel.>/2
      :lt -> &Kernel.</2
    end
    """

    assert analyze(source) == []
  end

  test "leaves good code alone" do
    assert analyze("def foo(x), do: x + 1") == []
  end

  test "leaves capture with valid syntax alone" do
    assert analyze("Enum.map(list, &(&1 + 1))") == []
  end

  # The deliberately-skipped shapes below all parse as valid Elixir today. The
  # rule refuses to touch them, so it must not flag them either.

  test "does not flag a capture whose body is a bitstring literal" do
    assert analyze("Enum.map(list, &<<&1>>)") == []
  end

  test "does not flag && followed by a bitstring literal" do
    assert analyze("x = a&&<<1>>") == []
  end

  test "does not flag &&& followed by a bitstring literal" do
    assert analyze("x = a&&&<<1>>") == []
  end

  test "does not flag the shift operators" do
    assert analyze("x = y <<< 2") == []
    assert analyze("def f(x), do: x >>> 1") == []
  end

  test "does not flag a comment line" do
    assert analyze("# use &> when comparing") == []
  end

  test "does not flag text inside a string literal" do
    assert analyze(~S'msg = "compare with &> here"') == []
  end

  test "does not flag prose inside a heredoc" do
    source = """
    @moduledoc \"\"\"
    Use &> for greater-than.
    \"\"\"
    """

    assert analyze(source) == []
  end

  test "flags only the code line in a file whose prose and valid code look similar" do
    source = """
    defmodule Cmp do
      @moduledoc \"\"\"
      Use &> for greater-than.
      \"\"\"

      def pack(l), do: Enum.map(l, &<<&1>>)
      def mask(a), do: a&&<<1>>
      def label, do: "the &< operator"
      def picker, do: &>
    end
    """

    assert [%Issue{meta: %{line: 9}}] = analyze(source)
  end
end
