defmodule Credence.Pattern.NoTrailingNewlineInDocFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoTrailingNewlineInDoc

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoTrailingNewlineInDoc, code, [])
  end

  describe "strips trailing newline from single-line strings" do
    test "@doc trailing newline" do
      code = """
      defmodule Example do
        @doc "Finds the missing number.\\n"
        def missing_number(list), do: 0
      end
      """

      expected = """
      defmodule Example do
        @doc "Finds the missing number."
        def missing_number(list), do: 0
      end
      """

      assert fix(code) == expected
    end

    test "@moduledoc trailing newline" do
      code = """
      defmodule Example do
        @moduledoc "A module for palindrome checking.\\n"
        def palindrome?(s), do: s == String.reverse(s)
      end
      """

      expected = """
      defmodule Example do
        @moduledoc "A module for palindrome checking."
        def palindrome?(s), do: s == String.reverse(s)
      end
      """

      assert fix(code) == expected
    end

    test "@typedoc trailing newline" do
      code = """
      defmodule Example do
        @typedoc "A custom type.\\n"
        @type t :: :ok | :error
      end
      """

      expected = """
      defmodule Example do
        @typedoc "A custom type."
        @type t :: :ok | :error
      end
      """

      assert fix(code) == expected
    end

    test "multiple trailing newlines" do
      code = """
      defmodule Example do
        @doc "Some text.\\n\\n"
        def foo, do: :ok
      end
      """

      expected = """
      defmodule Example do
        @doc "Some text."
        def foo, do: :ok
      end
      """

      assert fix(code) == expected
    end

    test "multiple doc attrs in one file" do
      code = """
      defmodule Example do
        @moduledoc "Module doc.\\n"

        @doc "Function doc.\\n"
        def foo, do: :ok
      end
      """

      expected = """
      defmodule Example do
        @moduledoc "Module doc."

        @doc "Function doc."
        def foo, do: :ok
      end
      """

      assert fix(code) == expected
    end

    test "preserves surrounding code" do
      code = """
      defmodule Example do
        @moduledoc "Module.\\n"

        @spec missing_number([integer]) :: integer
        @doc "Finds it.\\n"
        def missing_number(list), do: 0
      end
      """

      expected = """
      defmodule Example do
        @moduledoc "Module."

        @spec missing_number([integer]) :: integer
        @doc "Finds it."
        def missing_number(list), do: 0
      end
      """

      assert fix(code) == expected
    end
  end

  describe "does not modify heredocs" do
    test "leaves single-line heredoc @doc unchanged" do
      code = ~S'''
      defmodule Example do
        @doc """
        Validates binary search trees.
        """
        def validate(tree), do: true
      end
      '''

      assert fix(code) == code
    end

    test "leaves single-line heredoc @moduledoc unchanged" do
      code = ~S'''
      defmodule BSTValidator do
        @moduledoc """
        BinarySearchTreeValidator validates binary search trees.
        """
        def validate(tree), do: true
      end
      '''

      assert fix(code) == code
    end

    test "leaves multi-line heredoc @doc unchanged" do
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

      assert fix(code) == code
    end
  end

  describe "no-ops" do
    test "does not modify multi-line single-string doc" do
      code = """
      defmodule Example do
        @doc "Line one.\\nLine two.\\n"
        def foo, do: :ok
      end
      """

      assert fix(code) == code
    end

    test "returns source unchanged when nothing to fix" do
      code = """
      defmodule Example do
        @doc "Clean doc."
        def foo, do: :ok
      end
      """

      assert fix(code) == code
    end

    test "does not touch @doc false" do
      code = """
      defmodule Example do
        @doc false
        def foo, do: :ok
      end
      """

      assert fix(code) == code
    end
  end
end
