defmodule Credence.Pattern.NoTrailingNewlineInDocTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoTrailingNewlineInDoc.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoTrailingNewlineInDoc.fix(code, [])
  end

  describe "fixable?/0" do
    test "reports as fixable" do
      assert Credence.Pattern.NoTrailingNewlineInDoc.fixable?() == true
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # CHECK TESTS
  # ═══════════════════════════════════════════════════════════════════

  describe "check/2 — positive cases" do
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

      # After parsing, value is "Some text.\n\n" — trim trailing \n gives "Some text."
      # which has no internal \n. So it IS flagged.
      [issue] = check(code)
      assert issue.rule == :no_trailing_newline_in_doc
    end
  end

  describe "check/2 — negative cases" do
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
      # Multi-line @doc values (like heredocs) have internal \n — not flagged
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
      # Multi-line doc string (not trailing-only)
      code = """
      defmodule Example do
        @doc "Line one.\\nLine two."
        def foo, do: :ok
      end
      """

      assert check(code) == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX TESTS
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/2" do
    test "strips trailing newline from @doc" do
      code = """
      defmodule Example do
        @doc "Finds the missing number.\\n"
        def missing_number(list), do: 0
      end
      """

      fixed = fix(code)
      assert fixed =~ ~S|@doc "Finds the missing number."|
      refute fixed =~ ~S|\n"|
    end

    test "strips trailing newline from @moduledoc" do
      code = """
      defmodule Example do
        @moduledoc "A module for palindrome checking.\\n"
        def palindrome?(s), do: s == String.reverse(s)
      end
      """

      fixed = fix(code)
      assert fixed =~ ~S|@moduledoc "A module for palindrome checking."|
    end

    test "strips trailing newline from @typedoc" do
      code = """
      defmodule Example do
        @typedoc "A custom type.\\n"
        @type t :: :ok | :error
      end
      """

      fixed = fix(code)
      assert fixed =~ ~S|@typedoc "A custom type."|
    end

    test "strips multiple trailing newlines" do
      code = """
      defmodule Example do
        @doc "Some text.\\n\\n"
        def foo, do: :ok
      end
      """

      fixed = fix(code)
      assert fixed =~ ~S|@doc "Some text."|
    end

    test "fixes multiple doc attrs in one file" do
      code = """
      defmodule Example do
        @moduledoc "Module doc.\\n"

        @doc "Function doc.\\n"
        def foo, do: :ok
      end
      """

      fixed = fix(code)
      assert fixed =~ ~S|@moduledoc "Module doc."|
      assert fixed =~ ~S|@doc "Function doc."|
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

      fixed = fix(code)
      assert fixed =~ "@spec missing_number"
      assert fixed =~ "def missing_number(list)"
      assert fixed =~ ~S|@moduledoc "Module."|
      assert fixed =~ ~S|@doc "Finds it."|
    end

    test "does not modify multi-line doc strings" do
      # Multi-line @doc (like heredocs) have internal \n so aren't targeted
      code = """
      defmodule Example do
        @doc "Line one.\\nLine two.\\n"
        def foo, do: :ok
      end
      """

      # Not targeted by fix since it has internal newlines
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
