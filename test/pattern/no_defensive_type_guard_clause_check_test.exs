defmodule Credence.Pattern.NoDefensiveTypeGuardClauseCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoDefensiveTypeGuardClause

  describe "flags the anti-pattern" do
    test "flags `when not is_integer(n)` guard" do
      code = """
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

      issues = check(NoDefensiveTypeGuardClause, code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_defensive_type_guard_clause
    end

    test "flags `when not is_binary(s)` guard" do
      code = """
      defmodule Example do
        def foo(s) when not is_binary(s) do
          :error
        end

        def foo(s) do
          String.upcase(s)
        end
      end
      """

      assert flagged?(NoDefensiveTypeGuardClause, code)
    end

    test "flags `when not is_list(l)` guard" do
      code = """
      defmodule Example do
        def bar(l) when not is_list(l) do
          :error
        end

        def bar(l) do
          Enum.sum(l)
        end
      end
      """

      assert flagged?(NoDefensiveTypeGuardClause, code)
    end
  end

  describe "leaves good code alone" do
    test "no negated type guard" do
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

      assert clean?(NoDefensiveTypeGuardClause, code)
    end

    test "compound guard with negated type check is not flagged" do
      code = """
      defmodule Example do
        def foo(n) when not is_integer(n) and n > 0 do
          :ok
        end

        def foo(_n) do
          :error
        end
      end
      """

      assert clean?(NoDefensiveTypeGuardClause, code)
    end

    test "plain function call without guard" do
      code = """
      defmodule Example do
        def add(a, b) do
          a + b
        end
      end
      """

      assert clean?(NoDefensiveTypeGuardClause, code)
    end
  end
end
