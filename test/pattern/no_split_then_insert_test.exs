defmodule Credence.Pattern.NoSplitThenInsertTest do
  use ExUnit.Case

  alias Credence.Pattern.NoSplitThenInsert

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoSplitThenInsert.check(ast, [])
  end

  defp fix(code),
    do: Credence.RuleHelpers.apply_rule_fix(NoSplitThenInsert, code, [])

  describe "check" do
    test "detects Enum.split followed by left ++ [elem] ++ right" do
      code = """
      defmodule M do
        def insert_all(element, list) do
          Enum.map(0..length(list), fn i ->
            {left, right} = Enum.split(list, i)
            left ++ [element] ++ right
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_split_then_insert
    end

    test "detects with cons cell form: left ++ [elem | right]" do
      code = """
      defmodule M do
        def insert(element, list, i) do
          {left, right} = Enum.split(list, i)
          left ++ [element | right]
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_split_then_insert
    end

    test "does not flag Enum.split when halves are used for other purposes" do
      code = """
      defmodule M do
        def process(list, i) do
          {left, right} = Enum.split(list, i)
          total = Enum.sum(left) + Enum.sum(right)
          total
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when more than one element is inserted" do
      code = """
      defmodule M do
        def splice(list, i, new_items) do
          {left, right} = Enum.split(list, i)
          left ++ new_items ++ right
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when left is reused after the insertion" do
      code = """
      defmodule M do
        def f(list, i, elem) do
          {left, right} = Enum.split(list, i)
          result = left ++ [elem] ++ right
          {result, left}
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    test "replaces split + concat with List.insert_at" do
      code = """
      Enum.map(0..length(list), fn i ->
        {left, right} = Enum.split(list, i)
        left ++ [element] ++ right
      end)
      """

      result = fix(code)
      assert result =~ "List.insert_at(list, i, element)"
      refute result =~ "Enum.split"
      refute result =~ "left ++"
    end

    test "replaces cons cell form" do
      code = """
      {left, right} = Enum.split(list, i)
      left ++ [element | right]
      """

      result = fix(code)
      assert result =~ "List.insert_at(list, i, element)"
      refute result =~ "Enum.split"
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def perms(chars) do
          Enum.map(0..length(chars), fn i ->
            {left, right} = Enum.split(chars, i)
            left ++ [element] ++ right
          end)
        end
      end
      """

      result = fix(code)
      assert result =~ "def perms(chars)"
      assert result =~ "Enum.map"
      assert result =~ "List.insert_at(chars, i, element)"
    end

    test "round-trip: fixed code produces no issues" do
      code = """
      Enum.map(0..length(list), fn i ->
        {left, right} = Enum.split(list, i)
        left ++ [element] ++ right
      end)
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoSplitThenInsert.check(ast, []) == []
    end
  end
end
