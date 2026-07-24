defmodule Credence.Syntax.FixCaptureOperatorSyntaxFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixCaptureOperatorSyntax

  defp analyze(code), do: FixCaptureOperatorSyntax.analyze(code)
  defp fix(code), do: FixCaptureOperatorSyntax.fix(code)

  test "fixes &> to &Kernel.>/2" do
    input = ":gt -> &>"
    expected = ":gt -> &Kernel.>/2"

    confirm_fix(fix(input), expected)
  end

  test "fixes &< to &Kernel.</2" do
    input = ":lt -> &<"
    expected = ":lt -> &Kernel.</2"

    confirm_fix(fix(input), expected)
  end

  test "fixes &>= to &Kernel.>=/2" do
    input = ":gte -> &>="
    expected = ":gte -> &Kernel.>=/2"

    confirm_fix(fix(input), expected)
  end

  test "fixes &<= to &Kernel.<=/2" do
    input = ":lte -> &<="
    expected = ":lte -> &Kernel.<=/2"

    confirm_fix(fix(input), expected)
  end

  test "fixes all four capture operators in a case block" do
    input = ~S"""
    case op_name do
      :gt -> &>
      :lt -> &<
      :gte -> &>=
      :lte -> &<=
    end
    """

    expected = ~S"""
    case op_name do
      :gt -> &Kernel.>/2
      :lt -> &Kernel.</2
      :gte -> &Kernel.>=/2
      :lte -> &Kernel.<=/2
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes two capture operators on one line" do
    confirm_fix(fix("[&>, &<]"), "[&Kernel.>/2, &Kernel.</2]")
  end

  test "fixes a capture operator passed as an argument" do
    confirm_fix(fix("Enum.sort(list, &>)"), "Enum.sort(list, &Kernel.>/2)")
  end

  test "fixes a capture operator followed by a trailing comment" do
    confirm_fix(fix(":gt -> &> # greater"), ":gt -> &Kernel.>/2 # greater")
  end

  test "fixed output no longer flags" do
    input = ":gt -> &>"
    assert analyze(fix(input)) == []
  end

  test "fixed output no longer flags for all operators" do
    source = """
    case op_name do
      :gt -> &>
      :lt -> &<
      :gte -> &>=
      :lte -> &<=
    end
    """

    assert analyze(fix(source)) == []
  end

  test "fixing twice changes nothing the second time" do
    source = """
    case op_name do
      :gt -> &>
      :lt -> &<
    end
    """

    once = fix(source)
    confirm_fix(fix(once), once)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    case op_name do
      :gt -> &>
    end
    """

    refute valid_syntax?(input)
    assert valid_syntax?(fix(input))
  end

  test "does not modify valid Kernel captures" do
    source = ":gt -> &Kernel.>/2"
    confirm_fix(fix(source), source)
  end

  test "does not modify pipe operator" do
    source = "x |> foo() |> bar()"
    confirm_fix(fix(source), source)
  end

  test "does not modify capture with other operators" do
    source = "Enum.map(list, &(&1 + 1))"
    confirm_fix(fix(source), source)
  end

  # The shapes below parse as valid Elixir. A bare `&<` / `&>` scan would mangle
  # them into code that no longer parses, so the fix must leave them byte-exact.

  test "does not modify a capture whose body is a bitstring literal" do
    source = "Enum.map(list, &<<&1>>)"
    assert valid_syntax?(source)
    confirm_fix(fix(source), source)
  end

  test "does not modify && followed by a bitstring literal" do
    source = "x = a&&<<1>>"
    assert valid_syntax?(source)
    confirm_fix(fix(source), source)
  end

  test "does not modify &&& followed by a bitstring literal" do
    source = "x = a&&&<<1>>"
    assert valid_syntax?(source)
    confirm_fix(fix(source), source)
  end

  test "does not modify the shift operators" do
    source = "x = y <<< 2"
    confirm_fix(fix(source), source)
  end

  test "does not modify a comment line" do
    source = "# use &> when comparing"
    confirm_fix(fix(source), source)
  end

  test "does not modify text inside a string literal" do
    source = ~S'msg = "compare with &> here"'
    confirm_fix(fix(source), source)
  end

  test "does not modify prose inside a heredoc" do
    source = """
    @moduledoc \"\"\"
    Use &> for greater-than.
    \"\"\"
    """

    confirm_fix(fix(source), source)
  end

  test "repairs only the broken line of a module full of look-alikes" do
    input = """
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

    expected = """
    defmodule Cmp do
      @moduledoc \"\"\"
      Use &> for greater-than.
      \"\"\"

      def pack(l), do: Enum.map(l, &<<&1>>)
      def mask(a), do: a&&<<1>>
      def label, do: "the &< operator"
      def picker, do: &Kernel.>/2
    end
    """

    refute valid_syntax?(input)
    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))
  end

  test "preserves multibyte content on earlier lines" do
    input = """
    label = "café 👩‍🔬"
    cmp = &>=
    """

    expected = """
    label = "café 👩‍🔬"
    cmp = &Kernel.>=/2
    """

    confirm_fix(fix(input), expected)
  end

  test "leaves an empty source alone" do
    confirm_fix(fix(""), "")
  end
end
