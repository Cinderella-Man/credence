defmodule Credence.Pattern.NoDocFalseOnPrivateTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoDocFalseOnPrivate

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoDocFalseOnPrivate.check(ast, [])
  end

  defp fix(code) do
    ast = Sourceror.parse_string!(code)
    patches = NoDocFalseOnPrivate.fix_patches(ast, [])

    if patches == [] do
      code
    else
      Sourceror.patch_string(code, patches)
    end
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

      assert issue.message =~ "discarded"
      assert issue.meta.line != nil
    end

    test "detects @doc with content before defp" do
      code = """
      defmodule Bad do
        @doc "Calculates something"
        defp compute(x), do: x + 1
        def run(x), do: compute(x)
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_doc_false_on_private
      assert issue.message =~ "discarded"
    end

    test "detects @doc heredoc before defp" do
      code = """
      defmodule Bad do
        @doc \"\"\"
        Multi-line doc on private function.
        \"\"\"
        defp process(x), do: x + 1
        def run(x), do: process(x)
      end
      """

      issues = check(code)

      assert length(issues) == 1
    end

    test "detects @doc before @spec then defp" do
      code = """
      defmodule Bad do
        @doc "Sums multiples"
        @spec sum_of(integer()) :: integer()
        defp sum_of(x), do: x
        def run(x), do: sum_of(x)
      end
      """

      issues = check(code)

      assert length(issues) == 1
    end

    test "detects multiple @doc on defp" do
      code = """
      defmodule Bad do
        @doc false
        defp helper1(x), do: x + 1

        @doc "Does something"
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

    test "passes @doc not followed by defp" do
      code = """
      defmodule Good do
        @doc "Public API"
        def run(x), do: x

        defp helper(x), do: x + 1
      end
      """

      assert check(code) == []
    end
  end

  describe "fix_patches/2" do
    test "removes @doc false before defp" do
      code = """
      defmodule Fix1 do
        @doc false
        defp helper(x), do: x + 1
        def run(x), do: helper(x)
      end
      """

      expected = """
      defmodule Fix1 do
        defp helper(x), do: x + 1
        def run(x), do: helper(x)
      end
      """

      assert fix(code) == expected
    end

    test "removes @doc with content before defp" do
      code = """
      defmodule Fix2 do
        @doc "Does something"
        defp helper(x), do: x + 1
        def run(x), do: helper(x)
      end
      """

      expected = """
      defmodule Fix2 do
        defp helper(x), do: x + 1
        def run(x), do: helper(x)
      end
      """

      assert fix(code) == expected
    end

    test "removes @doc heredoc before defp" do
      code = """
      defmodule Fix3 do
        @doc \"\"\"
        Multi-line doc.
        \"\"\"
        defp helper(x), do: x + 1
        def run(x), do: helper(x)
      end
      """

      expected = """
      defmodule Fix3 do
        defp helper(x), do: x + 1
        def run(x), do: helper(x)
      end
      """

      assert fix(code) == expected
    end

    test "removes @doc before @spec then defp" do
      code = """
      defmodule Fix4 do
        @doc "Sums multiples"
        @spec sum_of(integer()) :: integer()
        defp sum_of(x), do: x
        def run(x), do: sum_of(x)
      end
      """

      expected = """
      defmodule Fix4 do
        @spec sum_of(integer()) :: integer()
        defp sum_of(x), do: x
        def run(x), do: sum_of(x)
      end
      """

      assert fix(code) == expected
    end

    test "does not remove @doc on public function" do
      code = """
      defmodule Good do
        @doc "Public API"
        def run(x), do: x
      end
      """

      assert fix(code) == code
    end
  end
end
