defmodule Credence.Pattern.NoRedundantToListTest do
  use ExUnit.Case

  alias Credence.Pattern.NoRedundantToList

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoRedundantToList.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoRedundantToList, code, [])
  end

  describe "check/2" do
    test "fires on Enum.to_list(x) |> MapSet.new()" do
      code = """
      defmodule Example do
        def run(items) do
          Enum.to_list(items) |> MapSet.new()
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_redundant_to_list
    end

    test "fires on x |> Enum.to_list() |> MapSet.new()" do
      code = """
      defmodule Example do
        def run(items) do
          items |> Enum.to_list() |> MapSet.new()
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "fires on MapSet.new(Enum.to_list(x))" do
      code = """
      defmodule Example do
        def run(items) do
          MapSet.new(Enum.to_list(items))
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "fires on Enum.to_list |> Map.new" do
      code = """
      defmodule Example do
        def run(items) do
          Enum.to_list(items) |> Map.new()
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "fires on multiple occurrences in same module" do
      code = """
      defmodule Example do
        def run(a, b) do
          first = Enum.to_list(a) |> MapSet.new()
          second = Enum.to_list(b) |> MapSet.new()
          {first, second}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end

    test "does not fire on MapSet.new(items)" do
      code = """
      defmodule Example do
        def run(items) do
          MapSet.new(items)
        end
      end
      """

      assert check(code) == []
    end

    test "does not fire on Enum.to_list used alone" do
      code = """
      defmodule Example do
        def run(items) do
          Enum.to_list(items)
        end
      end
      """

      assert check(code) == []
    end

    test "does not fire on Enum.to_list piped to arbitrary function" do
      code = """
      defmodule Example do
        def run(items) do
          Enum.to_list(items) |> IO.inspect()
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix/2" do
    test "fixes Enum.to_list(x) |> MapSet.new() to MapSet.new(x)" do
      code = "Enum.to_list(items) |> MapSet.new()"
      result = fix(code)
      assert result =~ "MapSet.new(items)"
      refute result =~ "Enum.to_list"
    end

    test "fixes x |> Enum.to_list() |> MapSet.new() to MapSet.new(x)" do
      code = "items |> Enum.to_list() |> MapSet.new()"
      result = fix(code)
      assert result =~ "MapSet.new(items)"
      refute result =~ "Enum.to_list"
    end

    test "fixes MapSet.new(Enum.to_list(x)) to MapSet.new(x)" do
      code = "MapSet.new(Enum.to_list(items))"
      result = fix(code)
      assert result =~ "MapSet.new(items)"
      refute result =~ "Enum.to_list"
    end

    test "preserves surrounding code" do
      code = """
      defmodule Solution do
        def run(first_list, second_list) do
          first_set = Enum.to_list(first_list) |> MapSet.new()
          second_set = Enum.to_list(second_list) |> MapSet.new()
          {first_set, second_set}
        end
      end
      """

      result = fix(code)
      assert result =~ "MapSet.new(first_list)"
      assert result =~ "MapSet.new(second_list)"
      assert result =~ "{first_set, second_set}"
    end

    test "fixed code produces no issues" do
      code = """
      defmodule RoundTrip do
        def run(items) do
          Enum.to_list(items) |> MapSet.new()
        end
      end
      """

      fixed = fix(code)
      {:ok, fixed_ast} = Sourceror.parse_string(fixed)
      issues = NoRedundantToList.check(fixed_ast, [])
      assert issues == []
    end

    test "preserves additional args in pipe" do
      code = "Enum.to_list(pairs) |> Map.new()"
      result = fix(code)
      assert result =~ "Map.new(pairs)"
      refute result =~ "Enum.to_list"
    end
  end
end
