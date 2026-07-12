defmodule Credence.Syntax.FixKeywordBeforePositionalArgumentAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixKeywordBeforePositionalArgument

  defp analyze(code), do: FixKeywordBeforePositionalArgument.analyze(code)

  describe "flags keyword args before positional args" do
    test "keyword before empty list" do
      assert [%Issue{rule: :fix_keyword_before_positional_argument}] =
               analyze("Task.Supervisor.start_link(name: __MODULE__, [])")
    end

    test "keyword before positional identifier" do
      assert [%Issue{rule: :fix_keyword_before_positional_argument}] =
               analyze("foo(name: x, arg)")
    end

    test "multiple keywords before positional" do
      assert [%Issue{rule: :fix_keyword_before_positional_argument}] =
               analyze("foo(key1: 1, key2: 2, arg)")
    end

    test "inside defmodule" do
      input = """
      defmodule TaskSupervisor do
        def start_child do
          Task.Supervisor.start_link(name: __MODULE__, [])
        end
      end
      """

      assert [%Issue{rule: :fix_keyword_before_positional_argument, meta: %{line: 3}}] =
               analyze(input)
    end
  end

  describe "leaves good code alone" do
    test "keywords after positional (valid)" do
      assert analyze("foo(bar, name: __MODULE__)") == []
    end

    test "only keywords" do
      assert analyze("foo(name: x, age: 30)") == []
    end

    test "no arguments" do
      assert analyze("foo()") == []
    end

    test "single positional argument" do
      assert analyze("foo(bar)") == []
    end

    test "keywords at end of multi-arg call" do
      assert analyze("Task.Supervisor.start_link([], name: __MODULE__)") == []
    end
  end
end
