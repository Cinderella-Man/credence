defmodule Credence.Syntax.FixKeywordBeforePositionalArgumentFixTest do
  use ExUnit.Case, async: true

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixKeywordBeforePositionalArgument

  defp analyze(code), do: FixKeywordBeforePositionalArgument.analyze(code)
  defp fix(code), do: FixKeywordBeforePositionalArgument.fix(code)

  describe "fixes keyword-before-positional argument order" do
    test "single keyword before empty list" do
      input = "Task.Supervisor.start_link(name: __MODULE__, [])"

      expected = "Task.Supervisor.start_link([], name: __MODULE__)"

      confirm_fix(fix(input), expected)
    end

    test "single keyword before identifier" do
      input = "foo(name: x, arg)"

      expected = "foo(arg, name: x)"

      confirm_fix(fix(input), expected)
    end

    test "multiple keywords before positional" do
      input = "foo(key1: 1, key2: 2, arg)"

      expected = "foo(arg, key1: 1, key2: 2)"

      confirm_fix(fix(input), expected)
    end

    test "keyword sandwiched between positionals" do
      input = "foo(a, name: x, b)"

      expected = "foo(a, b, name: x)"

      confirm_fix(fix(input), expected)
    end

    test "nested call as the trailing positional" do
      input = "foo(name: 1, bar(2))"

      expected = "foo(bar(2), name: 1)"

      confirm_fix(fix(input), expected)
    end

    test "list and tuple positionals keep their internal commas" do
      input = "foo(name: 1, [a, b], {c, d})"

      expected = "foo([a, b], {c, d}, name: 1)"

      confirm_fix(fix(input), expected)
    end

    test "unicode identifiers are preserved" do
      input = "foo(a: ärg_ünicode, brg)"

      expected = "foo(brg, a: ärg_ünicode)"

      confirm_fix(fix(input), expected)
    end

    test "unicode keyword names are recognized" do
      input = "foo(árg: 1, positional)"
      expected = "foo(positional, árg: 1)"
      actual = fix(input)

      confirm_fix(actual, expected)
      assert valid_syntax?(actual)
      confirm_fix(fix(actual), actual)
    end

    test "inside defmodule multiline" do
      input = """
      defmodule TaskSupervisor do
        def start_child do
          Task.Supervisor.start_link(name: __MODULE__, [])
        end
      end
      """

      expected = """
      defmodule TaskSupervisor do
        def start_child do
          Task.Supervisor.start_link([], name: __MODULE__)
        end
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "call spread over several lines collapses onto one" do
      input = """
      foo(
        name: x,
        arg
      )
      """

      expected = "foo(arg, name: x)"

      confirm_fix(fix(input), expected)
    end

    test "two broken calls in one module are both repaired" do
      input = """
      defmodule M do
        def a, do: foo(name: 1, x)
        def b, do: bar(key: 2, y)
      end
      """

      expected = """
      defmodule M do
        def a, do: foo(x, name: 1)
        def b, do: bar(y, key: 2)
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "more than twenty broken calls are all repaired" do
      input = Enum.map_join(1..21, "\n", fn i -> "foo(k: #{i}, p#{i})" end)
      expected = Enum.map_join(1..21, "\n", fn i -> "foo(p#{i}, k: #{i})" end)
      actual = fix(input)

      confirm_fix(actual, expected)
      assert valid_syntax?(actual)
      confirm_fix(fix(actual), actual)
    end
  end

  describe "leaves correct code unchanged" do
    test "keywords at end (valid)" do
      source = "foo(bar, name: __MODULE__)"

      confirm_fix(fix(source), source)
    end

    test "only keywords" do
      source = "foo(name: x, age: 30)"

      confirm_fix(fix(source), source)
    end

    test "empty source" do
      confirm_fix(fix(""), "")
    end

    test "a whole module that parses" do
      source = """
      defmodule TaskSupervisor do
        def start_child do
          Task.Supervisor.start_link([], name: __MODULE__)
        end
      end
      """

      confirm_fix(fix(source), source)
    end
  end

  describe "leaves parse errors it does not own unchanged" do
    test "stray end (tuple-shaped error message)" do
      source = """
      def f do
        1
      end
      end
      """

      confirm_fix(fix(source), source)
    end

    test "missing terminator" do
      source = """
      defmodule M do
        def f do
          :ok
      end
      """

      confirm_fix(fix(source), source)
    end

    test "unclosed paren" do
      source = "foo(1, 2"

      confirm_fix(fix(source), source)
    end
  end

  describe "declines the cases the textual split cannot be trusted on" do
    # A naive split would rewrite `foo(a: ",", b)` into `foo(", b, a: ")` — a
    # different program that happens to parse. The rule refuses instead.
    test "comma inside a string literal" do
      source = ~S'foo(a: ",", b)'

      confirm_fix(fix(source), source)
    end

    test "string argument without a comma" do
      source = ~S'foo(name: "x", arg)'

      confirm_fix(fix(source), source)
    end

    test "charlist argument" do
      source = "foo(name: 'x', arg)"

      confirm_fix(fix(source), source)
    end

    test "comment inside the argument list" do
      source = """
      foo(
        name: x, # why
        arg
      )
      """

      confirm_fix(fix(source), source)
    end

    test "sigil argument" do
      source = "foo(name: ~w(a b), arg)"

      confirm_fix(fix(source), source)
    end

    test "char literal argument" do
      source = "foo(name: ?,, arg)"

      confirm_fix(fix(source), source)
    end

    test "clause arrow in the argument list" do
      source = "foo(name: 1, fn x -> x end, arg)"

      confirm_fix(fix(source), source)
    end
  end

  describe "fixed output no longer flags" do
    test "single keyword before empty list" do
      assert analyze(fix("Task.Supervisor.start_link(name: __MODULE__, [])")) == []
    end

    test "multiple keywords before positional" do
      assert analyze(fix("foo(key1: 1, key2: 2, arg)")) == []
    end

    test "two broken calls in one module" do
      input = """
      defmodule M do
        def a, do: foo(name: 1, x)
        def b, do: bar(key: 2, y)
      end
      """

      assert analyze(fix(input)) == []
    end

    test "inside defmodule" do
      input = """
      defmodule TaskSupervisor do
        def start_child do
          Task.Supervisor.start_link(name: __MODULE__, [])
        end
      end
      """

      assert analyze(fix(input)) == []
    end
  end

  describe "fixed output is well-formed (parses)" do
    test "single keyword before empty list" do
      assert valid_syntax?(fix("Task.Supervisor.start_link(name: __MODULE__, [])"))
    end

    test "call spread over several lines" do
      input = """
      foo(
        name: x,
        arg
      )
      """

      assert valid_syntax?(fix(input))
    end

    test "inside defmodule" do
      input = """
      defmodule TaskSupervisor do
        def start_child do
          Task.Supervisor.start_link(name: __MODULE__, [])
        end
      end
      """

      assert valid_syntax?(fix(input))
    end
  end
end
