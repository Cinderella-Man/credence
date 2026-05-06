defmodule Credence.Pattern.NoEnumAtMidpointAccessTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoEnumAtMidpointAccess.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoEnumAtMidpointAccess.fix(code, [])
  end

  describe "fixable?" do
    test "reports as fixable" do
      assert Credence.Pattern.NoEnumAtMidpointAccess.fixable?() == true
    end
  end

  describe "detects non-recursive midpoint access patterns" do
    test "flags Enum.at with mid from low + div(high - low, 2)" do
      code = """
      defmodule Search do
        def find(list, low, high) do
          mid = low + div(high - low, 2)
          Enum.at(list, mid)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      issue = hd(issues)
      assert issue.rule == :no_enum_at_midpoint_access
      assert issue.message =~ "List.to_tuple/1"
      assert issue.meta.line != nil
    end

    test "flags Enum.at with mid from div(low + high, 2)" do
      code = """
      defmodule Search do
        def find(list, low, high) do
          mid = div(low + high, 2)
          Enum.at(list, mid)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags Enum.at with mid from div(high - low, 2) + low" do
      code = """
      defmodule Search do
        def find(list, low, high) do
          mid = div(high - low, 2) + low
          Enum.at(list, mid)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags inline midpoint expression" do
      code = """
      defmodule Inline do
        def find(list, low, high) do
          Enum.at(list, div(low + high, 2))
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags piped Enum.at with midpoint variable" do
      code = """
      defmodule Piped do
        def find(list, low, high) do
          mid = low + div(high - low, 2)
          list |> Enum.at(mid)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags piped Enum.at with inline midpoint" do
      code = """
      defmodule Piped do
        def find(list, low, high) do
          list |> Enum.at(div(low + high, 2))
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags multiple list variables" do
      code = """
      defmodule Multi do
        def compare(keys, values, low, high) do
          mid = low + div(high - low, 2)
          k = Enum.at(keys, mid)
          v = Enum.at(values, mid)
          {k, v}
        end
      end
      """

      assert length(check(code)) == 2
    end

    test "flags Enum.at inside anonymous fn (reduce_while pattern)" do
      code = """
      defmodule Iterative do
        def search(list, target) do
          Enum.reduce_while(0..100, {0, length(list) - 1}, fn _, {low, high} ->
            mid = low + div(high - low, 2)
            mid_val = Enum.at(list, mid)

            cond do
              mid_val == target -> {:halt, {:ok, mid}}
              mid_val < target -> {:cont, {mid + 1, high}}
              true -> {:cont, {low, mid - 1}}
            end
          end)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags defp functions" do
      code = """
      defmodule Private do
        defp lookup(list, low, high) do
          mid = div(low + high, 2)
          Enum.at(list, mid)
        end
      end
      """

      assert length(check(code)) == 1
    end
  end

  describe "ignores recursive functions" do
    test "does not flag recursive function" do
      code = """
      defmodule Recursive do
        def search(list, target, low, high) when low <= high do
          mid = low + div(high - low, 2)
          mid_val = Enum.at(list, mid)

          cond do
            mid_val == target -> mid
            mid_val < target -> search(list, target, mid + 1, high)
            true -> search(list, target, low, mid - 1)
          end
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "ignores safe code" do
    test "passes code using elem/tuple" do
      code = """
      defmodule Fast do
        def find(tuple, low, high) do
          mid = div(low + high, 2)
          elem(tuple, mid)
        end
      end
      """

      assert check(code) == []
    end

    test "passes Enum.at with literal indices" do
      code = """
      defmodule Config do
        def first(list) do
          Enum.at(list, 0)
        end
      end
      """

      assert check(code) == []
    end

    test "passes Enum.at with simple dynamic index" do
      code = """
      defmodule Example do
        def get(list, i) do
          Enum.at(list, i)
        end
      end
      """

      assert check(code) == []
    end

    test "passes when mid is a parameter, not derived from midpoint math" do
      code = """
      defmodule Example do
        def foo(list, mid) do
          Enum.at(list, mid)
        end
      end
      """

      assert check(code) == []
    end

    test "passes when mid comes from non-midpoint expression" do
      code = """
      defmodule Other do
        def foo(list) do
          mid = String.length("hello")
          Enum.at(list, mid)
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix: direct call with midpoint variable" do
    test "inserts List.to_tuple and replaces Enum.at with elem" do
      code = """
      defmodule Search do
        def find(list, low, high) do
          mid = low + div(high - low, 2)
          mid_val = Enum.at(list, mid)
          mid_val
        end
      end
      """

      result = fix(code)

      assert result =~ "List.to_tuple(list)"
      assert result =~ ~r/elem\(\s*list_tuple,\s*mid\s*\)/
      refute result =~ "Enum.at"
    end
  end

  describe "fix: piped call" do
    test "replaces piped Enum.at with elem" do
      code = """
      defmodule Piped do
        def find(list, low, high) do
          mid = low + div(high - low, 2)
          list |> Enum.at(mid)
        end
      end
      """

      result = fix(code)

      assert result =~ "List.to_tuple(list)"
      assert result =~ ~r/elem\(\s*list_tuple,\s*mid\s*\)/
      refute result =~ "Enum.at"
      refute result =~ "|>"
    end
  end

  describe "fix: inline midpoint expression" do
    test "replaces inline midpoint Enum.at with elem" do
      code = """
      defmodule Inline do
        def find(list, low, high) do
          Enum.at(list, div(low + high, 2))
        end
      end
      """

      result = fix(code)

      assert result =~ "List.to_tuple(list)"
      assert result =~ ~r/elem\(\s*list_tuple,/
      refute result =~ "Enum.at"
    end
  end

  describe "fix: multiple lists" do
    test "creates a tuple variable for each list" do
      code = """
      defmodule Multi do
        def compare(keys, values, low, high) do
          mid = low + div(high - low, 2)
          k = Enum.at(keys, mid)
          v = Enum.at(values, mid)
          {k, v}
        end
      end
      """

      result = fix(code)

      assert result =~ "List.to_tuple(keys)"
      assert result =~ "List.to_tuple(values)"
      assert result =~ ~r/elem\(\s*keys_tuple,\s*mid\s*\)/
      assert result =~ ~r/elem\(\s*values_tuple,\s*mid\s*\)/
      refute result =~ "Enum.at"
    end
  end

  describe "fix: anonymous function (reduce_while)" do
    test "inserts conversion at top of enclosing def, not inside fn" do
      code = """
      defmodule Iterative do
        def search(list, target) do
          Enum.reduce_while(0..100, {0, length(list) - 1}, fn _, {low, high} ->
            mid = low + div(high - low, 2)
            mid_val = Enum.at(list, mid)

            cond do
              mid_val == target -> {:halt, {:ok, mid}}
              mid_val < target -> {:cont, {mid + 1, high}}
              true -> {:cont, {low, mid - 1}}
            end
          end)
        end
      end
      """

      result = fix(code)

      assert result =~ "List.to_tuple(list)"
      assert result =~ ~r/elem\(\s*list_tuple,\s*mid\s*\)/
      refute result =~ "Enum.at"
    end
  end

  describe "fix: defp functions" do
    test "fixes private functions too" do
      code = """
      defmodule Private do
        defp lookup(list, low, high) do
          mid = div(low + high, 2)
          Enum.at(list, mid)
        end
      end
      """

      result = fix(code)

      assert result =~ "List.to_tuple(list)"
      assert result =~ ~r/elem\(\s*list_tuple,\s*mid\s*\)/
      refute result =~ "Enum.at"
    end
  end

  describe "fix skips recursive functions" do
    test "leaves recursive function unchanged" do
      code = """
      defmodule Recursive do
        def search(list, target, low, high) when low <= high do
          mid = low + div(high - low, 2)
          mid_val = Enum.at(list, mid)

          cond do
            mid_val == target -> mid
            mid_val < target -> search(list, target, mid + 1, high)
            true -> search(list, target, low, mid - 1)
          end
        end
      end
      """

      result = fix(code)

      assert result =~ "Enum.at(list, mid)"
      refute result =~ "List.to_tuple"
      refute result =~ "elem("
    end
  end

  describe "fix preserves unrelated code" do
    test "does not modify functions without flagged Enum.at" do
      code = """
      defmodule Safe do
        def get(list, i) do
          Enum.at(list, i)
        end
      end
      """

      result = fix(code)

      assert result =~ "Enum.at(list, i)"
      refute result =~ "List.to_tuple"
    end

    test "only fixes the flagged function, leaves others alone" do
      code = """
      defmodule Mixed do
        def safe_get(list, i) do
          Enum.at(list, i)
        end

        def bad_search(list, low, high) do
          mid = div(low + high, 2)
          Enum.at(list, mid)
        end
      end
      """

      result = fix(code)

      # bad_search fixed
      assert result =~ ~r/elem\(\s*list_tuple,\s*mid\s*\)/
      # safe_get untouched
      assert result =~ "Enum.at(list, i)"
    end
  end

  describe "fix round-trip" do
    test "fixed code produces no check issues (direct call)" do
      code = """
      defmodule RoundTrip do
        def find(list, low, high) do
          mid = low + div(high - low, 2)
          Enum.at(list, mid)
        end
      end
      """

      fixed = fix(code)
      {:ok, fixed_ast} = Code.string_to_quoted(fixed)
      assert Credence.Pattern.NoEnumAtMidpointAccess.check(fixed_ast, []) == []
    end

    test "fixed code produces no check issues (piped)" do
      code = """
      defmodule RoundTrip do
        def find(list, low, high) do
          mid = div(low + high, 2)
          list |> Enum.at(mid)
        end
      end
      """

      fixed = fix(code)
      {:ok, fixed_ast} = Code.string_to_quoted(fixed)
      assert Credence.Pattern.NoEnumAtMidpointAccess.check(fixed_ast, []) == []
    end

    test "fixed code produces no check issues (inline midpoint)" do
      code = """
      defmodule RoundTrip do
        def find(list, low, high) do
          Enum.at(list, div(low + high, 2))
        end
      end
      """

      fixed = fix(code)
      {:ok, fixed_ast} = Code.string_to_quoted(fixed)
      assert Credence.Pattern.NoEnumAtMidpointAccess.check(fixed_ast, []) == []
    end

    test "fixed code produces no check issues (multiple lists)" do
      code = """
      defmodule RoundTrip do
        def compare(keys, values, low, high) do
          mid = low + div(high - low, 2)
          k = Enum.at(keys, mid)
          v = Enum.at(values, mid)
          {k, v}
        end
      end
      """

      fixed = fix(code)
      {:ok, fixed_ast} = Code.string_to_quoted(fixed)
      assert Credence.Pattern.NoEnumAtMidpointAccess.check(fixed_ast, []) == []
    end
  end
end
