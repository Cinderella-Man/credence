defmodule Credence.Pattern.NoTrailingNewlineInDocCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoTrailingNewlineInDoc

  describe "flags single-line docs with trailing newline" do
    test "flags @doc with trailing newline" do
      code = """
      defmodule Example do
        @doc "Finds the missing number.\\n"
        def missing_number(list), do: 0
      end
      """

      [issue] = check(NoTrailingNewlineInDoc, code)
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

      [issue] = check(NoTrailingNewlineInDoc, code)
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

      [issue] = check(NoTrailingNewlineInDoc, code)
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

      issues = check(NoTrailingNewlineInDoc, code)
      assert length(issues) == 2
    end

    test "flags doc with multiple trailing newlines" do
      code = """
      defmodule Example do
        @doc "Some text.\\n\\n"
        def foo, do: :ok
      end
      """

      [issue] = check(NoTrailingNewlineInDoc, code)
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

      assert check(NoTrailingNewlineInDoc, code) == []
    end

    test "does not flag @doc false" do
      code = """
      defmodule Example do
        @doc false
        def internal, do: :ok
      end
      """

      assert check(NoTrailingNewlineInDoc, code) == []
    end

    test "does not flag @moduledoc false" do
      code = """
      defmodule Example do
        @moduledoc false
        def foo, do: :ok
      end
      """

      assert check(NoTrailingNewlineInDoc, code) == []
    end

    test "does not flag multi-line doc string with trailing newline" do
      code = """
      defmodule Example do
        @doc "Finds the missing number.\\nReturns an integer.\\n"
        def missing_number(list), do: 0
      end
      """

      assert check(NoTrailingNewlineInDoc, code) == []
    end

    test "does not flag unrelated module attributes" do
      code = """
      defmodule Example do
        @my_attr "some value\\n"
        def foo, do: @my_attr
      end
      """

      assert check(NoTrailingNewlineInDoc, code) == []
    end

    test "does not flag @doc with only internal newlines" do
      code = """
      defmodule Example do
        @doc "Line one.\\nLine two."
        def foo, do: :ok
      end
      """

      assert check(NoTrailingNewlineInDoc, code) == []
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

      assert check(NoTrailingNewlineInDoc, code) == []
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

      assert check(NoTrailingNewlineInDoc, code) == []
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

      assert check(NoTrailingNewlineInDoc, code) == []
    end

    test "still flags single-line string @doc even with source available" do
      code = """
      defmodule Example do
        @doc "Trailing newline here.\\n"
        def foo, do: :ok
      end
      """

      [issue] = check(NoTrailingNewlineInDoc, code)
      assert issue.rule == :no_trailing_newline_in_doc
    end
  end

  # Regression, and it shipped as a defect. Sourceror hands back the RAW text
  # between the quotes, so a doc documenting a literal backslash followed by the
  # letter `n` arrives with those exact characters — no newline anywhere in it.
  # The old test was `String.ends_with?(value, "\\n")`, which only looks at the
  # last two characters, so it fired. The fix then removed two characters and left
  # a dangling backslash escaping the closing quote, the output did not parse, and
  # `apply_rule_fix_with_status/3` discarded the patch — six findings reported and
  # never repaired. A real escape needs an ODD run of backslashes before the `n`.
  describe "does not flag an escaped backslash followed by n" do
    test "at the end of the doc" do
      code = """
      defmodule EscBsA do
        @doc "a windows path C:\\\\n"
        def foo, do: :ok
      end
      """

      assert clean?(NoTrailingNewlineInDoc, code)
    end

    test "and the fix leaves it byte-identical" do
      code = """
      defmodule EscBsB do
        @doc "a windows path C:\\\\n"
        def foo, do: :ok
      end
      """

      confirm_fix(fix(NoTrailingNewlineInDoc, code), code)
      assert valid_syntax?(fix(NoTrailingNewlineInDoc, code))
    end
  end
end
