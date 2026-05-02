defmodule Credence.Rule.NoIsPrefixForNonGuardTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoIsPrefixForNonGuard.check(ast, [])
  end

  describe "NoIsPrefixForNonGuard" do
    test "detects def is_palindrome" do
      code = """
      defmodule Bad do
        def is_palindrome(str), do: str == String.reverse(str)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_is_prefix_for_non_guard

      assert issue.message =~ "is_palindrome"
      assert issue.message =~ "palindrome?"
    end

    test "detects defp is_palindrome" do
      code = """
      defmodule Bad do
        defp is_palindrome(list), do: list == Enum.reverse(list)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "defp"
      assert issue.message =~ "palindrome?"
    end

    test "detects def is_valid_ipv4" do
      code = """
      defmodule Bad do
        def is_valid_ipv4(ip) when is_binary(ip) do
          parts = String.split(ip, ".")
          length(parts) == 4
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "is_valid_ipv4"
      assert issue.message =~ "valid_ipv4?"
    end

    test "detects def is_power_of_two" do
      code = """
      defmodule Bad do
        def is_power_of_two(1), do: true
        def is_power_of_two(n) when rem(n, 2) == 0, do: is_power_of_two(div(n, 2))
        def is_power_of_two(_), do: false
      end
      """

      issues = check(code)
      assert length(issues) == 3
      assert Enum.all?(issues, &(&1.message =~ "power_of_two?"))
    end

    test "detects def is_anagram" do
      code = """
      defmodule Bad do
        def is_anagram(str1, str2) do
          Enum.frequencies(String.graphemes(str1)) ==
            Enum.frequencies(String.graphemes(str2))
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "is_anagram"
      assert issue.message =~ "anagram?"
    end

    test "detects def is_permutation with guard" do
      code = """
      defmodule Bad do
        def is_permutation(arr) when is_list(arr) do
          true
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "is_permutation"
      assert issue.message =~ "permutation?"
    end

    test "detects def is_perfect_square" do
      code = """
      defmodule Bad do
        def is_perfect_square(n) when is_integer(n) and n >= 0 do
          root = trunc(:math.sqrt(n))
          root * root == n
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "perfect_square?"
    end

    test "suggests valid_foo? for is_valid_foo names" do
      code = """
      defmodule Bad do
        def is_valid_email(str), do: String.contains?(str, "@")
      end
      """

      [issue] = check(code)
      assert issue.message =~ "valid_email?"
    end

    # ---- Negative cases ----

    test "does not flag question-mark functions" do
      code = """
      defmodule Good do
        def palindrome?(str), do: str == String.reverse(str)
        def valid_ipv4?(ip), do: true
      end
      """

      assert check(code) == []
    end

    test "does not flag defguard" do
      code = """
      defmodule Good do
        defguard is_positive(n) when is_integer(n) and n > 0
      end
      """

      assert check(code) == []
    end

    test "does not flag defguardp" do
      code = """
      defmodule Good do
        defguardp is_valid_age(age) when is_integer(age) and age >= 0 and age <= 150
      end
      """

      assert check(code) == []
    end

    test "does not flag defmacro" do
      code = """
      defmodule Good do
        defmacro is_special(val) do
          quote do: unquote(val) in [:a, :b]
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag functions without is_ prefix" do
      code = """
      defmodule Good do
        def validate(input), do: true
        defp check_bounds(n), do: n > 0
      end
      """

      assert check(code) == []
    end

    test "does not flag is_ functions that also end with ?" do
      code = """
      defmodule Good do
        def is_empty?(list), do: list == []
      end
      """

      assert check(code) == []
    end

    test "does not flag non-function nodes" do
      code = """
      defmodule Good do
        @is_enabled true
        def foo, do: @is_enabled
      end
      """

      assert check(code) == []
    end
  end
end
