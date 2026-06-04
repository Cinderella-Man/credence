defmodule Credence.Pattern.NoIsPrefixForNonGuardFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoIsPrefixForNonGuard

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoIsPrefixForNonGuard, code, [])
  end

  describe "fix/2" do
    test "renames simple def is_palindrome to palindrome?" do
      code = """
      defmodule Example do
        def is_palindrome(str), do: str == String.reverse(str)
      end
      """

      expected = """
      defmodule Example do
        def palindrome?(str), do: str == String.reverse(str)
      end
      """

      assert fix(code) == expected
    end

    test "renames defp is_valid to valid?" do
      code = """
      defmodule Example do
        defp is_valid(x), do: x != nil
      end
      """

      expected = """
      defmodule Example do
        defp valid?(x), do: x != nil
      end
      """

      assert fix(code) == expected
    end

    test "renames multi-word is_valid_email to valid_email?" do
      code = """
      defmodule Example do
        def is_valid_email(str), do: String.contains?(str, "@")
      end
      """

      expected = """
      defmodule Example do
        def valid_email?(str), do: String.contains?(str, "@")
      end
      """

      assert fix(code) == expected
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

      expected = """
      defmodule Example do
        def valid_ipv4?(ip) when is_binary(ip) do
          parts = String.split(ip, ".")
          length(parts) == 4
        end
      end
      """

      assert fix(code) == expected
    end

    test "renames recursive calls" do
      code = """
      defmodule Example do
        def is_power_of_two(1), do: true
        def is_power_of_two(n) when rem(n, 2) == 0, do: is_power_of_two(div(n, 2))
        def is_power_of_two(_), do: false
      end
      """

      expected = """
      defmodule Example do
        def power_of_two?(1), do: true
        def power_of_two?(n) when rem(n, 2) == 0, do: power_of_two?(div(n, 2))
        def power_of_two?(_), do: false
      end
      """

      assert fix(code) == expected
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

      expected = """
      defmodule Example do
        def even?(n), do: rem(n, 2) == 0

        def run(n) do
          if even?(n), do: :yes, else: :no
        end
      end
      """

      assert fix(code) == expected
    end

    test "does not rename qualified calls to other modules" do
      code = """
      defmodule Example do
        def is_valid(x) do
          Validator.is_valid(x)
        end
      end
      """

      expected = """
      defmodule Example do
        def valid?(x) do
          Validator.is_valid(x)
        end
      end
      """

      assert fix(code) == expected
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

      assert fix(code) == code
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

      expected = """
      defmodule Example do
        def valid?(x), do: x != nil
        def ready?(x), do: x == :ready

        def run(x) do
          valid?(x) and ready?(x)
        end
      end
      """

      assert fix(code) == expected
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

      expected = """
      defmodule Example do
        def positive?(n), do: n > 0

        def run(n) do
          n |> positive?()
        end
      end
      """

      assert fix(code) == expected
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

      expected = """
      defmodule Example do
        def perfect_square?(n) when is_integer(n) and n >= 0 do
          root = trunc(:math.sqrt(n))
          root * root == n
        end
      end
      """

      assert fix(code) == expected
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

      expected = """
      defmodule Example do
        def positive?(n), do: n > 0

        def run(list) do
          Enum.filter(list, &positive?/1)
        end
      end
      """

      assert fix(code) == expected
    end

    test "auto_fix_public: false skips public `def` (external callers invisible)" do
      code = """
      defmodule Example do
        def is_public(x), do: x
        defp is_private(x), do: x
      end
      """

      expected = """
      defmodule Example do
        def is_public(x), do: x
        defp private?(x), do: x
      end
      """

      fixed =
        Credence.RuleHelpers.apply_rule_fix(
          NoIsPrefixForNonGuard,
          code,
          auto_fix_public: false
        )

      assert fixed == expected
    end

    test "auto_fix_public defaults to true (renames both def and defp)" do
      code = """
      defmodule Example do
        def is_public(x), do: x
      end
      """

      expected = """
      defmodule Example do
        def public?(x), do: x
      end
      """

      fixed = Credence.RuleHelpers.apply_rule_fix(NoIsPrefixForNonGuard, code, [])

      assert fixed == expected
    end

    # --- DELTA: redundant "double convention" (is_ prefix AND ? suffix) ---

    test "renames is_palindrome? to palindrome? (strip prefix, keep ?)" do
      code = """
      defmodule Example do
        defp is_palindrome?(num) do
          str = Integer.to_string(num)
          str == String.reverse(str)
        end

        def check(n) do
          if is_palindrome?(n), do: :yes, else: :no
        end
      end
      """

      expected = """
      defmodule Example do
        defp palindrome?(num) do
          str = Integer.to_string(num)
          str == String.reverse(str)
        end

        def check(n) do
          if palindrome?(n), do: :yes, else: :no
        end
      end
      """

      assert fix(code) == expected
    end

    test "renames is_empty? to empty? (strip prefix, keep ?)" do
      code = """
      defmodule Example do
        def is_empty?(list), do: list == []

        def check(list) do
          is_empty?(list)
        end
      end
      """

      expected = """
      defmodule Example do
        def empty?(list), do: list == []

        def check(list) do
          empty?(list)
        end
      end
      """

      assert fix(code) == expected
    end
  end
end
