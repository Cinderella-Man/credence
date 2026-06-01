defmodule Credence.Pattern.NoFindValueDefaultCaseTest do
  use ExUnit.Case

  alias Credence.Pattern.NoFindValueDefaultCase

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoFindValueDefaultCase.check(ast, [])
  end

  defp fix(code),
    do: Credence.RuleHelpers.apply_rule_fix(NoFindValueDefaultCase, code, [])

  describe "check" do
    test "detects case Enum.find_value/2 with nil -> default identity" do
      code = """
      case Enum.find_value(list, &process/1) do
        nil -> :default
        val -> val
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_find_value_default_case
    end

    test "detects case Enum.find/2 with nil -> default identity" do
      code = """
      case Enum.find(list, &valid?/1) do
        nil -> :not_found
        val -> val
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_find_value_default_case
    end

    test "detects Enum.find_value/2 || default" do
      code = """
      Enum.find_value(list, &process/1) || :default
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_find_value_default_case
    end

    test "detects Enum.find/2 || default" do
      code = """
      Enum.find(list, &valid?/1) || :not_found
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_find_value_default_case
    end

    test "detects piped case: Enum.find_value/2 |> case do" do
      code = """
      Enum.find_value(list, &process/1)
      |> case do
        nil -> :default
        val -> val
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_find_value_default_case
    end

    test "detects 2-arg pipe case: Enum.find_value(coll, fun) |> case" do
      code = """
      Enum.find_value(list, fun)
      |> case do
        nil -> :default
        val -> val
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_find_value_default_case
    end

    test "reversed clauses: val -> val first, nil -> default second" do
      code = """
      case Enum.find_value(list, fun) do
        val -> val
        nil -> :default
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "does NOT flag Enum.find_value/3 (already has default)" do
      code = """
      case Enum.find_value(list, :default, &process/1) do
        nil -> :other
        val -> val
      end
      """

      assert check(code) == []
    end

    test "does NOT flag Enum.find/3 (already has default)" do
      code = """
      Enum.find(list, :default, &valid?/1)
      """

      assert check(code) == []
    end

    test "does NOT flag when non-nil clause is not identity" do
      code = """
      case Enum.find_value(list, &process/1) do
        nil -> :default
        val -> transform(val)
      end
      """

      assert check(code) == []
    end

    test "does NOT flag when nil clause is missing" do
      code = """
      case Enum.find_value(list, &process/1) do
        :not_found -> :default
        val -> val
      end
      """

      assert check(code) == []
    end

    test "does NOT flag bare Enum.find_value/2 without nil check" do
      code = """
      Enum.find_value(list, &process/1)
      """

      assert check(code) == []
    end

    test "does NOT flag bare Enum.find/2 without nil check" do
      code = """
      Enum.find(list, &valid?/1)
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    test "replaces case Enum.find_value/2 with Enum.find_value/3" do
      code = """
      case Enum.find_value(list, &process/1) do
        nil -> :default
        val -> val
      end
      """

      result = fix(code)
      assert result =~ "Enum.find_value(list, :default, &process/1)"
      refute result =~ "case"
    end

    test "replaces case Enum.find/2 with Enum.find/3" do
      code = """
      case Enum.find(list, &valid?/1) do
        nil -> :not_found
        val -> val
      end
      """

      result = fix(code)
      assert result =~ "Enum.find(list, :not_found, &valid?/1)"
      refute result =~ "case"
    end

    test "replaces Enum.find_value/2 || default with Enum.find_value/3" do
      code = """
      Enum.find_value(list, &process/1) || :default
      """

      result = fix(code)
      assert result =~ "Enum.find_value(list, :default, &process/1)"
      refute result =~ "||"
    end

    test "replaces Enum.find/2 || default with Enum.find/3" do
      code = """
      Enum.find(list, &valid?/1) || :not_found
      """

      result = fix(code)
      assert result =~ "Enum.find(list, :not_found, &valid?/1)"
      refute result =~ "||"
    end

    test "replaces 2-arg piped case with Enum.find_value/3" do
      code = """
      Enum.find_value(list, fun)
      |> case do
        nil -> :default
        val -> val
      end
      """

      result = fix(code)
      assert result =~ "Enum.find_value(list, :default, fun)"
      refute result =~ "case"
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def find_it(list) do
          count = length(list)
          result = case Enum.find_value(list, &process/1) do
            nil -> :default
            val -> val
          end
          {count, result}
        end
      end
      """

      result = fix(code)
      assert result =~ "length(list)"
      assert result =~ "Enum.find_value(list, :default, &process/1)"
      assert result =~ "{count, result}"
    end

    test "round-trip: fixed code produces no issues" do
      code = """
      case Enum.find_value(list, &process/1) do
        nil -> :default
        val -> val
      end
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoFindValueDefaultCase.check(ast, []) == []
    end

    test "round-trip: || fix produces no issues" do
      code = """
      Enum.find(list, &valid?/1) || :not_found
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoFindValueDefaultCase.check(ast, []) == []
    end
  end
end
