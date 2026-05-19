defmodule Credence.Pattern.NoTrailingNewlineInDocCheckTest do
  use ExUnit.Case

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    Credence.Pattern.NoTrailingNewlineInDoc.check(ast, [])
  end

  defp check_with_source(code) do
    ast = Sourceror.parse_string!(code)
    Credence.Pattern.NoTrailingNewlineInDoc.check(ast, source: code)
  end
  describe "flags single-line docs with trailing newline" do
    test "flags @doc with trailing newline" do
      code = """
      defmodule Example do
        @doc "Finds the missing number.\\n"
        def missing_number(list), do: 0
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_trailing_newline_in_doc
      assert issue.message =~ "@doc"
      assert issue.message =~ "trailing"
    end

    test "flags @moduledoc with trailing newline" do
      code = """
      defmodule Example do
        @moduledoc "A module for palindrome checking.\\n"
        def palindrome?(s), do: s == String.reverse(s)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_trailing_newline_in_doc
      assert issue.message =~ "@moduledoc"
    end

    test "flags @typedoc with trailing newline" do
      code = """
      defmodule Example do
        @typedoc "A custom type.\\n"
        @type t :: :ok | :error
      end
      """

      [issue] = check(code)
      assert issue.message =~ "@typedoc"
    end

    test "flags multiple doc attrs with trailing newlines" do
      code = """
      defmodule Example do
        @moduledoc "Module doc.\\n"

        @doc "Function doc.\\n"
        def foo, do: :ok
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end

    test "flags doc with multiple trailing newlines" do
      code = """
      defmodule Example do
        @doc "Some text.\\n\\n"
        def foo, do: :ok
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_trailing_newline_in_doc
    end
  end

  describe "does NOT flag clean docs" do
    test "does not flag @doc without trailing newline" do
      code = """
      defmodule Example do
        @doc "Finds the missing number."
        def missing_number(list), do: 0
      end
      """

      assert check(code) == []
    end

    test "does not flag @doc false" do
      code = """
      defmodule Example do
        @doc false
        def internal, do: :ok
      end
      """

      assert check(code) == []
    end

    test "does not flag @moduledoc false" do
      code = """
      defmodule Example do
        @moduledoc false
        def foo, do: :ok
      end
      """

      assert check(code) == []
    end

    test "does not flag multi-line doc string with trailing newline" do
      code = """
      defmodule Example do
        @doc "Finds the missing number.\\nReturns an integer.\\n"
        def missing_number(list), do: 0
      end
      """

      assert check(code) == []
    end

    test "does not flag unrelated module attributes" do
      code = """
      defmodule Example do
        @my_attr "some value\\n"
        def foo, do: @my_attr
      end
      """

      assert check(code) == []
    end

    test "does not flag @doc with only internal newlines" do
      code = """
      defmodule Example do
        @doc "Line one.\\nLine two."
        def foo, do: :ok
      end
      """

      assert check(code) == []
    end
  end

  describe "does NOT flag heredocs (with source)" do
    test "does not flag single-line heredoc @doc" do
      code = ~S'''
      defmodule Example do
        @doc """
        Validates binary search trees.
        """
        def validate(tree), do: true
      end
      '''

      assert check_with_source(code) == []
    end

    test "does not flag single-line heredoc @moduledoc" do
      code = ~S'''
      defmodule BSTValidator do
        @moduledoc """
        BinarySearchTreeValidator validates binary search trees.
        """
        def validate(tree), do: true
      end
      '''

      assert check_with_source(code) == []
    end

    test "does not flag multi-line heredoc @doc" do
      code = ~S'''
      defmodule Example do
        @doc """
        Checks if a string is a palindrome.

        ## Examples

            iex> Example.palindrome?("racecar")
            true
        """
        def palindrome?(s), do: s == String.reverse(s)
      end
      '''

      assert check_with_source(code) == []
    end

    test "still flags single-line string @doc even with source available" do
      code = """
      defmodule Example do
        @doc "Trailing newline here.\\n"
        def foo, do: :ok
      end
      """

      [issue] = check_with_source(code)
      assert issue.rule == :no_trailing_newline_in_doc
    end
  end
end
