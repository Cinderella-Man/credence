defmodule Credence.Rule.NoDocFalseOnPrivateTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoDocFalseOnPrivate.check(ast, [])
  end

  describe "NoDocFalseOnPrivate" do
    test "passes defp without @doc false" do
      code = """
      defmodule Good do
        defp helper(x), do: x + 1
        def process(x), do: helper(x)
      end
      """

      assert check(code) == []
    end

    test "passes @doc false on public function" do
      code = """
      defmodule Good do
        @doc false
        def internal_api(x), do: x + 1
      end
      """

      assert check(code) == []
    end

    test "passes @doc with actual docs on public function" do
      code = """
      defmodule Good do
        @doc "Does something"
        def process(x), do: x + 1
      end
      """

      assert check(code) == []
    end

    test "detects @doc false before defp" do
      code = """
      defmodule Bad do
        @doc false
        defp helper(x), do: x + 1
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_doc_false_on_private

      assert issue.message =~ "redundant"
      assert issue.meta.line != nil
    end

    test "detects multiple @doc false before defp" do
      code = """
      defmodule Bad do
        @doc false
        defp helper1(x), do: x + 1

        @doc false
        defp helper2(x), do: x * 2
      end
      """

      issues = check(code)

      assert length(issues) == 2
    end

    test "detects @doc false before guarded defp" do
      code = """
      defmodule Bad do
        @doc false
        defp helper(x) when is_integer(x), do: x + 1
      end
      """

      issues = check(code)

      assert length(issues) == 1
    end
  end
end
