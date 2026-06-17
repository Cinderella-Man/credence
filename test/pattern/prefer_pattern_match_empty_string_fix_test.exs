defmodule Credence.Pattern.PreferPatternMatchEmptyStringFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferPatternMatchEmptyString

  describe "PreferPatternMatchEmptyString fix" do
    test "fixes byte_size(str) == 0 into \"\" = str pattern (body uses str)" do
      input = """
      defmodule Example do
        def reverse_left_words(str, _count) when byte_size(str) == 0, do: str
      end
      """

      expected = """
      defmodule Example do
        def reverse_left_words("" = str, _count), do: str
      end
      """

      confirm_fix(fix(PreferPatternMatchEmptyString, input), expected)
    end

    test "fixes byte_size(str) == 0 into \"\" pattern (body does not use str)" do
      input = """
      defmodule Example do
        def process(str) when byte_size(str) == 0, do: :empty
      end
      """

      expected = """
      defmodule Example do
        def process(""), do: :empty
      end
      """

      confirm_fix(fix(PreferPatternMatchEmptyString, input), expected)
    end

    test "fixes defp with byte_size guard" do
      input = """
      defmodule Example do
        defp empty?(str) when byte_size(str) == 0, do: true
      end
      """

      expected = """
      defmodule Example do
        defp empty?(""), do: true
      end
      """

      confirm_fix(fix(PreferPatternMatchEmptyString, input), expected)
    end

    test "preserves remaining guard in compound expression" do
      input = """
      defmodule Example do
        def process(str, x) when byte_size(str) == 0 and is_binary(x) do
          :ok
        end
      end
      """

      expected = """
      defmodule Example do
        def process("", x) when is_binary(x) do
          :ok
        end
      end
      """

      confirm_fix(fix(PreferPatternMatchEmptyString, input), expected)
    end

    test "keeps \"\" = var binding when the param is used in the remaining guard" do
      input = """
      defmodule Example do
        def f(str, x) when byte_size(str) == 0 and str == x, do: :ok
      end
      """

      expected = """
      defmodule Example do
        def f("" = str, x) when str == x, do: :ok
      end
      """

      confirm_fix(fix(PreferPatternMatchEmptyString, input), expected)
    end

    test "fixes byte_size conjunct alongside an independent or in the guard" do
      input = """
      defmodule Example do
        def f(str, a, b) when byte_size(str) == 0 and (a or b), do: :ok
      end
      """

      expected = """
      defmodule Example do
        def f("", a, b) when a or b, do: :ok
      end
      """

      confirm_fix(fix(PreferPatternMatchEmptyString, input), expected)
    end

    test "does not modify byte_size(var) == N for N != 0" do
      code = """
      defmodule Example do
        def check(str) when byte_size(str) == 5, do: :ok
      end
      """

      confirm_fix(fix(PreferPatternMatchEmptyString, code), code)
    end

    test "does not modify byte_size(var) != 0" do
      code = """
      defmodule Example do
        def check(str) when byte_size(str) != 0, do: :ok
      end
      """

      confirm_fix(fix(PreferPatternMatchEmptyString, code), code)
    end

    test "fixed code has no remaining issues" do
      code = """
      defmodule Example do
        def reverse_left_words(str, _count) when byte_size(str) == 0, do: str
        def reverse_left_words(str, count) do
          len = String.length(str)
          actual_count = rem(count, len)
          {left, right} = String.split_at(str, actual_count)
          right <> left
        end
      end
      """

      assert check(PreferPatternMatchEmptyString, fix(PreferPatternMatchEmptyString, code)) == []
    end

    test "preserves surrounding code" do
      code = """
      defmodule Example do
        def reverse_left_words(str, _count) when byte_size(str) == 0, do: str
        def reverse_left_words(str, count) do
          len = String.length(str)
          actual_count = rem(count, len)
          {left, right} = String.split_at(str, actual_count)
          right <> left
        end
      end
      """

      fixed = fix(PreferPatternMatchEmptyString, code)

      confirm_fix(fixed, """
      defmodule Example do
        def reverse_left_words("" = str, _count), do: str
        def reverse_left_words(str, count) do
          len = String.length(str)
          actual_count = rem(count, len)
          {left, right} = String.split_at(str, actual_count)
          right <> left
        end
      end
      """)
    end
  end
end
