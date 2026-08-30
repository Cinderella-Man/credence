defmodule Credence.Pattern.NoDocFalseOnPrivateCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoDocFalseOnPrivate

  describe "does not flag" do
    test "defp without @doc" do
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

    test "@doc with a string before defp" do
      issues =
        check(NoDocFalseOnPrivate, """
        defmodule Bad do
          @doc "Helper that finds the first unique character."
          defp find_first_unique(string), do: string
        end
        """)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_doc_false_on_private
      assert issue.message =~ "redundant"
      assert issue.meta.line != nil
    end

    test "multiple @doc before defp" do
      issues =
        check(NoDocFalseOnPrivate, """
        defmodule Bad do
          @doc false
          defp helper1(x), do: x + 1

          @doc "Some doc"
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

    test "@doc false before a defp with a spec" do
      issues =
        check(NoDocFalseOnPrivate, """
        defmodule BadWithSpec do
          @doc false
          @spec helper(integer()) :: integer()
          defp helper(x), do: x + 1
        end
        """)

      assert length(issues) == 1
      assert hd(issues).meta.line == 2
    end

    test "@doc with a string before a guarded defp" do
      issues =
        check(NoDocFalseOnPrivate, """
        defmodule Bad do
          @doc "Guarded helper"
          defp helper(x) when is_integer(x), do: x + 1
        end
        """)

      assert length(issues) == 1
    end
  end
end
