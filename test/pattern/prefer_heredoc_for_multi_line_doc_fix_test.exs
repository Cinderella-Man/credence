defmodule Credence.Pattern.PreferHeredocForMultiLineDocFixTest do
  use ExUnit.Case

  defp fix(code) do
    Credence.Pattern.PreferHeredocForMultiLineDoc.fix(code, [])
  end

  describe "fixable?/0" do
    test "reports as fixable" do
      assert Credence.Pattern.PreferHeredocForMultiLineDoc.fixable?() == true
    end
  end

  describe "fix/2 — conversions" do
    test "converts simple two-line @doc to heredoc" do
      code = """
      defmodule Example do
        @doc "Line one.\\nLine two."
        def foo, do: :ok
      end
      """

      expected = ~S'''
      defmodule Example do
        @doc """
        Line one.
        Line two.
        """
        def foo, do: :ok
      end
      '''

      assert fix(code) == expected
    end

    test "converts @moduledoc to heredoc" do
      code = """
      defmodule Example do
        @moduledoc "Module overview.\\nMore details."
        def foo, do: :ok
      end
      """

      expected = ~S'''
      defmodule Example do
        @moduledoc """
        Module overview.
        More details.
        """
        def foo, do: :ok
      end
      '''

      assert fix(code) == expected
    end

    test "converts @typedoc to heredoc" do
      code = """
      defmodule Example do
        @typedoc "A custom type.\\nWith explanation."
        @type t :: atom()
      end
      """

      expected = ~S'''
      defmodule Example do
        @typedoc """
        A custom type.
        With explanation.
        """
        @type t :: atom()
      end
      '''

      assert fix(code) == expected
    end

    test "strips trailing \\n in conversion" do
      code = """
      defmodule Example do
        @doc "Line one.\\nLine two.\\n"
        def foo, do: :ok
      end
      """

      expected = ~S'''
      defmodule Example do
        @doc """
        Line one.
        Line two.
        """
        def foo, do: :ok
      end
      '''

      assert fix(code) == expected
    end

    test "handles blank lines from consecutive \\n" do
      code = """
      defmodule Example do
        @doc "Summary.\\n\\nDetails here."
        def foo, do: :ok
      end
      """

      expected = ~S'''
      defmodule Example do
        @doc """
        Summary.

        Details here.
        """
        def foo, do: :ok
      end
      '''

      assert fix(code) == expected
    end

    test "preserves indentation at deeper nesting" do
      code = """
      defmodule Outer do
        defmodule Inner do
          @doc "Deep doc.\\nWith detail."
          def bar, do: :ok
        end
      end
      """

      expected = ~S'''
      defmodule Outer do
        defmodule Inner do
          @doc """
          Deep doc.
          With detail.
          """
          def bar, do: :ok
        end
      end
      '''

      assert fix(code) == expected
    end

    test "preserves surrounding code" do
      code = """
      defmodule Example do
        @spec foo() :: :ok
        @doc "Line one.\\nLine two."
        def foo, do: :ok

        def bar, do: :error
      end
      """

      expected = ~S'''
      defmodule Example do
        @spec foo() :: :ok
        @doc """
        Line one.
        Line two.
        """
        def foo, do: :ok

        def bar, do: :error
      end
      '''

      assert fix(code) == expected
    end

    test "handles escaped quotes in content" do
      code = """
      defmodule Example do
        @doc "Uses \\\"quotes\\\".\\nSecond line."
        def foo, do: :ok
      end
      """

      expected = ~S'''
      defmodule Example do
        @doc """
        Uses "quotes".
        Second line.
        """
        def foo, do: :ok
      end
      '''

      assert fix(code) == expected
    end

    test "fixes multiple doc attrs in one file" do
      code = """
      defmodule Example do
        @moduledoc "Module line1.\\nModule line2."

        @doc "Func line1.\\nFunc line2."
        def foo, do: :ok
      end
      """

      expected = ~S'''
      defmodule Example do
        @moduledoc """
        Module line1.
        Module line2.
        """

        @doc """
        Func line1.
        Func line2.
        """
        def foo, do: :ok
      end
      '''

      assert fix(code) == expected
    end

    test "handles LLM-style verbose doc with sections" do
      code = """
      defmodule Example do
        @doc "Counts occurrences.\\n\\n## Parameters\\n\\n- string: the input\\n- target: the char\\n"
        def count_char(s, t), do: 0
      end
      """

      expected = ~S'''
      defmodule Example do
        @doc """
        Counts occurrences.

        ## Parameters

        - string: the input
        - target: the char
        """
        def count_char(s, t), do: 0
      end
      '''

      assert fix(code) == expected
    end
  end

  describe "fix/2 — no-ops" do
    test "does not modify single-line @doc" do
      code = """
      defmodule Example do
        @doc "Simple doc."
        def foo, do: :ok
      end
      """

      assert fix(code) == code
    end

    test "does not modify @doc with only trailing \\n" do
      code = """
      defmodule Example do
        @doc "Simple doc.\\n"
        def foo, do: :ok
      end
      """

      assert fix(code) == code
    end

    test "returns source unchanged when nothing to fix" do
      code = """
      defmodule Example do
        def foo, do: :ok
      end
      """

      assert fix(code) == code
    end
  end

  describe "fix/2 — does not corrupt existing heredocs" do
    test "leaves @doc heredoc unchanged" do
      code = ~S'''
      defmodule Palindrome do
        @doc """
        Checks if a given string is a palindrome.

        ## Examples

            iex> Palindrome.palindrome?("racecar")
            true
        """
        @spec palindrome?(String.t()) :: boolean()
        def palindrome?(s), do: s == String.reverse(s)
      end
      '''

      assert fix(code) == code
    end

    test "leaves @doc heredoc with iex examples unchanged" do
      code = ~S'''
      defmodule MissingNumber do
        @doc """
        Finds the missing number in a sequence from 0 to n.

        ## Examples

            iex> MissingNumber.missing_number([9,6,4,2,3,5,7,0,1])
            8

            iex> MissingNumber.missing_number([0,1])
            2
        """
        @spec missing_number(list(integer())) :: integer()
        def missing_number(numbers), do: 0
      end
      '''

      assert fix(code) == code
    end

    test "leaves @moduledoc heredoc unchanged" do
      code = ~S'''
      defmodule MyApp do
        @moduledoc """
        Application entry point.

        Handles startup and configuration.
        """

        def start, do: :ok
      end
      '''

      assert fix(code) == code
    end

    test "converts single-line @doc without corrupting heredocs in same file" do
      code = ~S'''
      defmodule Example do
        @moduledoc """
        This module does things.

        It has multiple functions.
        """

        @doc "Func one.\nWith details."
        def foo, do: :ok

        @doc """
        Already a heredoc.

        Leave this alone.
        """
        def bar, do: :ok
      end
      '''

      expected = ~S'''
      defmodule Example do
        @moduledoc """
        This module does things.

        It has multiple functions.
        """

        @doc """
        Func one.
        With details.
        """
        def foo, do: :ok

        @doc """
        Already a heredoc.

        Leave this alone.
        """
        def bar, do: :ok
      end
      '''

      assert fix(code) == expected
    end
  end
end
