defmodule Credence.Pattern.NoDefensiveTypeGuardClauseFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoDefensiveTypeGuardClause

  describe "fix/2" do
    test "removes defensive type guard clause (spec example)" do
      input = """
      defmodule Solution do
        @spec check_power_of_two(integer()) :: boolean()
        def check_power_of_two(n) when not is_integer(n) do
          false
        end

        def check_power_of_two(n) when n <= 0 do
          false
        end

        def check_power_of_two(n) do
          Bitwise.band(n, n - 1) == 0
        end
      end
      """

      expected = """
      defmodule Solution do
        @spec check_power_of_two(integer()) :: boolean()
        def check_power_of_two(n) when n <= 0 do
          false
        end

        def check_power_of_two(n) do
          Bitwise.band(n, n - 1) == 0
        end
      end
      """

      assert fix(NoDefensiveTypeGuardClause, input) == expected
    end

    test "removes defensive guard from single-function module" do
      input = """
      defmodule Example do
        def foo(s) when not is_binary(s) do
          :error
        end

        def foo(s) do
          String.upcase(s)
        end
      end
      """

      expected = """
      defmodule Example do
        def foo(s) do
          String.upcase(s)
        end
      end
      """

      assert fix(NoDefensiveTypeGuardClause, input) == expected
    end

    test "no-op when no defensive guard is present" do
      code = """
      defmodule Solution do
        @spec check_power_of_two(integer()) :: boolean()
        def check_power_of_two(n) when n <= 0 do
          false
        end

        def check_power_of_two(n) do
          Bitwise.band(n, n - 1) == 0
        end
      end
      """

      assert fix(NoDefensiveTypeGuardClause, code) == code
    end
  end
end
