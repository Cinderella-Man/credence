defmodule Credence.Pattern.NoManualListReplaceAtTest do
  use ExUnit.Case

  alias Credence.Pattern.NoManualListReplaceAt

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoManualListReplaceAt.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoManualListReplaceAt, code, [])
  end

  describe "check" do
    test "flags defp reimplementing List.replace_at via Enum.split" do
      code = """
      defmodule M do
        defp replace_at(list, index, value) do
          {left, [_ | right]} = Enum.split(list, index)
          left ++ [value] ++ right
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_manual_list_replace_at
      assert issue.message =~ "List.replace_at/3"
    end

    test "flags defp reimplementing via List.split" do
      code = """
      defmodule M do
        defp replace_at(list, index, value) do
          {left, [_ | right]} = List.split(list, index)
          left ++ [value] ++ right
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_manual_list_replace_at
    end

    test "flags function with different name" do
      code = """
      defmodule M do
        defp set_element(list, idx, val) do
          {before, [_ | after_]} = Enum.split(list, idx)
          before ++ [val] ++ after_
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "List.replace_at/3"
    end

    test "flags public function (def)" do
      code = """
      defmodule M do
        def replace_at(list, index, value) do
          {left, [_ | right]} = Enum.split(list, index)
          left ++ [value] ++ right
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_manual_list_replace_at
    end

    test "does not flag List.replace_at usage" do
      code = """
      defmodule M do
        defp my_func(list, index, value) do
          List.replace_at(list, index, value)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag insert pattern (no wildcard head)" do
      code = """
      defmodule M do
        defp insert_at(list, index, value) do
          {before, after_} = Enum.split(list, index)
          before ++ [value] ++ after_
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag different body structure" do
      code = """
      defmodule M do
        defp replace_at(list, index, value) do
          Enum.split(list, index)
          value
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag wrong arity" do
      code = """
      defmodule M do
        defp replace_at(list, index) do
          {left, [_ | right]} = Enum.split(list, index)
          left ++ [0] ++ right
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when split result uses named head" do
      code = """
      defmodule M do
        defp replace_at(list, index, value) do
          {left, [head | right]} = Enum.split(list, index)
          left ++ [value] ++ right ++ [head]
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    test "replaces body with List.replace_at delegation" do
      code = """
      defmodule M do
        defp replace_at(list, index, value) do
          {left, [_ | right]} = Enum.split(list, index)
          left ++ [value] ++ right
        end
      end
      """

      result = fix(code)
      assert result =~ "List.replace_at(list, index, value)"
      refute result =~ "Enum.split"
    end
  end
end
