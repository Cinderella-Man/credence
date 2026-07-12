defmodule Credence.Syntax.FixKeywordBeforePositionalArgumentFixTest do
  use ExUnit.Case

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

    test "keyword in middle of args" do
      input = "foo(a, name: x, b)"
      expected = "foo(a, b, name: x)"
      confirm_fix(fix(input), expected)
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
  end

  describe "fixed output no longer flags" do
    test "single keyword before empty list" do
      assert analyze(fix("Task.Supervisor.start_link(name: __MODULE__, [])")) == []
    end

    test "multiple keywords before positional" do
      assert analyze(fix("foo(key1: 1, key2: 2, arg)")) == []
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
