defmodule Credence.Pattern.NoDocFalseOnPrivateCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoDocFalseOnPrivate

  describe "does not flag" do
    test "defp without @doc false" do
      assert clean?(NoDocFalseOnPrivate, """
             defmodule Good do
               defp helper(x), do: x + 1
               def process(x), do: helper(x)
             end
             """)
    end

    test "@doc false on a public function" do
      assert clean?(NoDocFalseOnPrivate, """
             defmodule Good do
               @doc false
               def internal_api(x), do: x + 1
             end
             """)
    end

    test "@doc with actual docs on a public function" do
      assert clean?(NoDocFalseOnPrivate, """
             defmodule Good do
               @doc "Does something"
               def process(x), do: x + 1
             end
             """)
    end
  end

  describe "flags" do
    test "@doc false before defp" do
      issues =
        check(NoDocFalseOnPrivate, """
        defmodule Bad do
          @doc false
          defp helper(x), do: x + 1
        end
        """)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_doc_false_on_private
      assert issue.message =~ "redundant"
      assert issue.meta.line != nil
    end

    test "multiple @doc false before defp" do
      issues =
        check(NoDocFalseOnPrivate, """
        defmodule Bad do
          @doc false
          defp helper1(x), do: x + 1

          @doc false
          defp helper2(x), do: x * 2
        end
        """)

      assert length(issues) == 2
    end

    test "@doc false before a guarded defp" do
      issues =
        check(NoDocFalseOnPrivate, """
        defmodule Bad do
          @doc false
          defp helper(x) when is_integer(x), do: x + 1
        end
        """)

      assert length(issues) == 1
    end
  end
end
