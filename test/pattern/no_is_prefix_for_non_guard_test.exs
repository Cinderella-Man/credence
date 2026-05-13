defmodule Credence.Pattern.NoIsPrefixForNonGuardTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoIsPrefixForNonGuard.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoIsPrefixForNonGuard.fix(code, [])
  end

  describe "check/2" do
    # --- POSITIVE CASES (should flag) ---

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

    # ---- NEGATIVE CASES (should NOT flag) ----

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

  describe "fixable?/0" do
    test "reports as fixable" do
      assert Credence.Pattern.NoIsPrefixForNonGuard.fixable?() == true
    end
  end

  describe "fix/2" do
    test "renames simple def is_palindrome to palindrome?" do
      code = """
      defmodule Example do
        def is_palindrome(str), do: str == String.reverse(str)
      end
      """

      fixed = fix(code)
      assert fixed =~ "def palindrome?(str)"
      refute fixed =~ "is_palindrome"
    end

    test "renames defp is_valid to valid?" do
      code = """
      defmodule Example do
        defp is_valid(x), do: x != nil
      end
      """

      fixed = fix(code)
      assert fixed =~ "defp valid?(x)"
      refute fixed =~ "is_valid"
    end

    test "renames multi-word is_valid_email to valid_email?" do
      code = """
      defmodule Example do
        def is_valid_email(str), do: String.contains?(str, "@")
      end
      """

      fixed = fix(code)
      assert fixed =~ "def valid_email?(str)"
      refute fixed =~ "is_valid_email"
    end

    test "renames function with guard and preserves Erlang guards" do
      code = """
      defmodule Example do
        def is_valid_ipv4(ip) when is_binary(ip) do
          parts = String.split(ip, ".")
          length(parts) == 4
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "def valid_ipv4?(ip)"
      # Erlang guard is_binary must NOT be renamed
      assert fixed =~ "is_binary(ip)"
      refute fixed =~ "is_valid_ipv4"
    end

    test "renames recursive calls" do
      code = """
      defmodule Example do
        def is_power_of_two(1), do: true
        def is_power_of_two(n) when rem(n, 2) == 0, do: is_power_of_two(div(n, 2))
        def is_power_of_two(_), do: false
      end
      """

      fixed = fix(code)
      # All definitions renamed
      refute fixed =~ "is_power_of_two"
      # All occurrences become power_of_two?
      assert fixed =~ "def power_of_two?(1)"
      assert fixed =~ "power_of_two?(div(n, 2))"
      assert fixed =~ "def power_of_two?(_)"
    end

    test "renames call sites in other functions within the same module" do
      code = """
      defmodule Example do
        def is_even(n), do: rem(n, 2) == 0

        def run(n) do
          if is_even(n), do: :yes, else: :no
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "def even?(n)"
      assert fixed =~ "if even?(n)"
      refute fixed =~ "is_even"
    end

    test "does not rename qualified calls to other modules" do
      code = """
      defmodule Example do
        def is_valid(x) do
          Validator.is_valid(x)
        end
      end
      """

      fixed = fix(code)
      # The local def is renamed
      assert fixed =~ "def valid?(x)"
      # The qualified call is NOT renamed (different AST shape)
      assert fixed =~ "Validator.is_valid(x)"
    end

    test "returns source unchanged when nothing to fix" do
      code = """
      defmodule Example do
        def palindrome?(str), do: str == String.reverse(str)
        def validate(input), do: true
      end
      """

      assert fix(code) == code
    end

    test "does not rename Erlang guard BIF wrappers" do
      code = """
      defmodule Example do
        def check(x) when is_list(x), do: :ok
      end
      """

      fixed = fix(code)
      assert fixed =~ "is_list(x)"
    end

    test "renames multiple different is_ functions in one module" do
      code = """
      defmodule Example do
        def is_valid(x), do: x != nil
        def is_ready(x), do: x == :ready

        def run(x) do
          is_valid(x) and is_ready(x)
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "def valid?(x)"
      assert fixed =~ "def ready?(x)"
      assert fixed =~ "valid?(x) and ready?(x)"
      refute fixed =~ "is_valid"
      refute fixed =~ "is_ready"
    end

    test "renames function used in pipeline" do
      code = """
      defmodule Example do
        def is_positive(n), do: n > 0

        def run(n) do
          n |> is_positive()
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "def positive?(n)"
      assert fixed =~ "|> positive?()"
      refute fixed =~ "is_positive"
    end

    test "handles function with multi-line body" do
      code = """
      defmodule Example do
        def is_perfect_square(n) when is_integer(n) and n >= 0 do
          root = trunc(:math.sqrt(n))
          root * root == n
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "def perfect_square?(n)"
      assert fixed =~ "is_integer(n)"
      refute fixed =~ "is_perfect_square"
    end

    test "renames capture references" do
      code = """
      defmodule Example do
        def is_positive(n), do: n > 0

        def run(list) do
          Enum.filter(list, &is_positive/1)
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "def positive?(n)"
      assert fixed =~ "&positive?/1"
      refute fixed =~ "is_positive"
    end

    test "auto_fix_public: false skips public `def` (external callers invisible)" do
      code = """
      defmodule Example do
        def is_public(x), do: x
        defp is_private(x), do: x
      end
      """

      fixed = Credence.Pattern.NoIsPrefixForNonGuard.fix(code, auto_fix_public: false)

      assert fixed =~ "def is_public(x)"
      assert fixed =~ "defp private?(x)"
    end

    test "auto_fix_public defaults to true (renames both def and defp)" do
      code = "defmodule Example do\n  def is_public(x), do: x\nend\n"

      fixed = Credence.Pattern.NoIsPrefixForNonGuard.fix(code, [])

      assert fixed =~ "def public?(x)"
    end
  end
end
