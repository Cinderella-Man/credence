defmodule Credence.Semantic.NoUndefinedGuardEqualityInCaseFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoUndefinedGuardEqualityInCase

  @real_message "invalid syntax found on credence_check.ex:81:18:\n    error: syntax error before: info\n    │\n 81 │         case :ets:info(:feature_flags) do\n    │                  ^\n    │\n    └─ credence_check.ex:81:18"

  defp fix(source, message \\ @real_message, line \\ 81) do
    NoUndefinedGuardEqualityInCase.fix(source, %{severity: :error, message: message, position: {line, 18}})
  end

  describe "fix/2" do
    test "replaces guard equality with direct pattern match" do
      input = """
      defmodule BadCaseUndefinedGuard do
        def check_table do
          table = :my_table
          case :ets.info(table) do
            undefined when undefined == :undefined -> :no_table
            _ -> :ok
          end
        end
      end
      """

      expected = """
      defmodule BadCaseUndefinedGuard do
        def check_table do
          table = :my_table
          case :ets.info(table) do
            :undefined -> :no_table
            _ -> :ok
          end
        end
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "handles different variable and atom names" do
      input = """
      defmodule M do
        def check(val) do
          case val do
            x when x == :ok -> :success
            _ -> :error
          end
        end
      end
      """

      expected = """
      defmodule M do
        def check(val) do
          case val do
            :ok -> :success
            _ -> :error
          end
        end
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "returns source unchanged when no guard equality pattern" do
      input = """
      defmodule GoodCaseUndefined do
        def check_table do
          table = :my_table
          case :ets.info(table) do
            :undefined -> :no_table
            _ -> :ok
          end
        end
      end
      """

      confirm_fix(fix(input), input)
    end

    test "fixed output is well-formed (parses)" do
      input = """
      defmodule BadCaseUndefinedGuard do
        def check_table do
          table = :my_table
          case :ets.info(table) do
            undefined when undefined == :undefined -> :no_table
            _ -> :ok
          end
        end
      end
      """

      assert valid_syntax?(fix(input))
    end
  end
end
