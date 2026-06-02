defmodule Credence.Pattern.NoStringSplitWhitespaceRegexTest do
  use ExUnit.Case

  alias Credence.Pattern.NoStringSplitWhitespaceRegex

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoStringSplitWhitespaceRegex.check(ast, [])
  end

  defp fix(code) do
    ast = Sourceror.parse_string!(code)
    patches = NoStringSplitWhitespaceRegex.fix_patches(ast, source: code)
    Sourceror.patch_string(code, patches)
  end

  describe "check" do
    test "detects String.split(x, ~r/\\s+/)" do
      code = """
      defmodule Bad do
        def parse(text) do
          String.split(text, ~r/\\s+/)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_string_split_whitespace_regex
      assert issue.message =~ "String.split/1"
    end

    test "detects String.split(x, ~r/\\s/, trim: true)" do
      code = """
      defmodule Bad do
        def parse(text) do
          String.split(text, ~r/\\s/, trim: true)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_string_split_whitespace_regex
    end

    test "detects piped String.split(~r/\\s+/)" do
      code = """
      defmodule Bad do
        def parse(text) do
          text
          |> String.split(~r/\\s+/)
          |> Enum.count()
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_string_split_whitespace_regex
    end

    test "detects multiple violations" do
      code = """
      defmodule Bad do
        def parse(a, b) do
          x = String.split(a, ~r/\\s+/)
          y = String.split(b, ~r/\\s/, trim: true)
          {x, y}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end

    # ---- Negative cases ----

    test "does not flag String.split/1 (already correct)" do
      code = """
      defmodule Good do
        def parse(text) do
          String.split(text)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag String.split/2 with non-whitespace regex" do
      code = """
      defmodule Good do
        def parse(text) do
          String.split(text, ~r/,/)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag String.split/2 with literal separator" do
      code = """
      defmodule Good do
        def parse(text) do
          String.split(text, ",")
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag String.split/2 with non-trim option" do
      code = """
      defmodule Good do
        def parse(text) do
          String.split(text, ~r/\\s/, parts: 3)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag ~r/\\s/ without trim option (not equivalent)" do
      code = """
      defmodule Good do
        def parse(text) do
          String.split(text, ~r/\\s/)
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    test "fixes String.split(x, ~r/\\s+/) → String.split(x)" do
      code = """
      defmodule Bad do
        def parse(text) do
          String.split(text, ~r/\\s+/)
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "String.split(text)"
      refute fixed =~ "~r"
    end

    test "fixes String.split(x, ~r/\\s/, trim: true) → String.split(x)" do
      code = """
      defmodule Bad do
        def parse(text) do
          String.split(text, ~r/\\s/, trim: true)
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "String.split(text)"
      refute fixed =~ "~r"
      refute fixed =~ "trim"
    end

    test "fixes piped String.split(~r/\\s+/) → String.split()" do
      code = """
      defmodule Bad do
        def parse(text) do
          text
          |> String.split(~r/\\s+/)
          |> length()
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "String.split()"
      refute fixed =~ "~r"
    end
  end
end
