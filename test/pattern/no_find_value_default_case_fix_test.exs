defmodule Credence.Pattern.NoFindValueDefaultCaseFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoFindValueDefaultCase

  describe "rewrites the safe core" do
    test "case Enum.find_value/2 -> Enum.find_value/3" do
      code = """
      case Enum.find_value(list, &process/1) do
        nil -> :default
        val -> val
      end
      """

      expected = "Enum.find_value(list, :default, &process/1)"

      confirm_fix(fix(NoFindValueDefaultCase, code), expected)
    end

    test "Enum.find_value/2 || default -> Enum.find_value/3" do
      code = "Enum.find_value(list, &process/1) || :default"

      expected = "Enum.find_value(list, :default, &process/1)"

      confirm_fix(fix(NoFindValueDefaultCase, code), expected)
    end

    test "piped case Enum.find_value/2 -> Enum.find_value/3" do
      code = """
      Enum.find_value(list, fun)
      |> case do
        nil -> :default
        val -> val
      end
      """

      expected = "Enum.find_value(list, :default, fun)"

      confirm_fix(fix(NoFindValueDefaultCase, code), expected)
    end

    test "1-arg pipe case -> Enum.find_value/3" do
      code = """
      list
      |> Enum.find_value(fun)
      |> case do
        nil -> :default
        val -> val
      end
      """

      expected = "Enum.find_value(list, :default, fun)"

      confirm_fix(fix(NoFindValueDefaultCase, code), expected)
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def find_it(list) do
          count = length(list)

          result =
            case Enum.find_value(list, &process/1) do
              nil -> :default
              val -> val
            end

          {count, result}
        end
      end
      """

      expected = """
      defmodule M do
        def find_it(list) do
          count = length(list)

          result =
            Enum.find_value(list, :default, &process/1)

          {count, result}
        end
      end
      """

      confirm_fix(fix(NoFindValueDefaultCase, code), expected)
    end

    test "round-trip: fixed code produces no issues" do
      code = """
      case Enum.find_value(list, &process/1) do
        nil -> :default
        val -> val
      end
      """

      fixed = fix(NoFindValueDefaultCase, code)
      assert clean?(NoFindValueDefaultCase, fixed)
    end
  end

  describe "leaves unsafe / out-of-scope code untouched" do
    test "reversed clauses unchanged" do
      code = """
      case Enum.find_value(list, fun) do
        val -> val
        nil -> :default
      end
      """

      confirm_fix(fix(NoFindValueDefaultCase, code), code)
    end

    test "Enum.find/2 nil-identity unchanged" do
      code = """
      case Enum.find(list, &valid?/1) do
        nil -> :not_found
        val -> val
      end
      """

      confirm_fix(fix(NoFindValueDefaultCase, code), code)
    end

    test "Enum.find/2 || default unchanged" do
      code = "Enum.find(list, &valid?/1) || :not_found"

      confirm_fix(fix(NoFindValueDefaultCase, code), code)
    end

    test "Enum.find/2 tuple extraction unchanged" do
      code = """
      case Enum.find(scores, fn {_k, v} -> v == target end) do
        {key, _} -> key
        nil -> -1
      end
      """

      confirm_fix(fix(NoFindValueDefaultCase, code), code)
    end
  end
end
