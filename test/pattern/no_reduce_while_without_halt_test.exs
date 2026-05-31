defmodule Credence.Pattern.NoReduceWhileWithoutHaltTest do
  use ExUnit.Case

  alias Credence.Pattern.NoReduceWhileWithoutHalt

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoReduceWhileWithoutHalt.check(ast, [])
  end

  defp fix(code),
    do: Credence.RuleHelpers.apply_rule_fix(NoReduceWhileWithoutHalt, code, [])

  describe "check" do
    test "passes code that uses Enum.reduce (not reduce_while)" do
      code = """
      defmodule Good do
        def total(list) do
          Enum.reduce(list, 0, fn x, acc -> acc + x end)
        end
      end
      """

      assert check(code) == []
    end

    test "detects reduce_while with single {:cont, _} clause" do
      code = """
      defmodule Bad do
        def total(list) do
          Enum.reduce_while(list, 0, fn x, acc ->
            {:cont, acc + x}
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_reduce_while_without_halt
    end

    test "detects reduce_while in pipeline with only {:cont, _}" do
      code = """
      defmodule Bad do
        def process(list) do
          list
          |> Enum.reduce_while({0, []}, fn h, {current_max, acc} ->
            new_max = max(h, current_max)
            {:cont, {new_max, [new_max | acc]}}
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_reduce_while_without_halt
    end

    test "passes when callback has a :halt clause" do
      code = """
      defmodule Good do
        def find_negative(list) do
          Enum.reduce_while(list, 0, fn x, acc ->
            if x < 0, do: {:halt, acc}, else: {:cont, acc + x}
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "passes when multi-clause fn has a :halt clause" do
      code = """
      defmodule Good do
        def process(list) do
          Enum.reduce_while(list, 0, fn
            :stop, acc -> {:halt, acc}
            x, acc -> {:cont, acc + x}
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "detects multi-clause fn where all clauses return {:cont, _}" do
      code = """
      defmodule Bad do
        def process(list) do
          Enum.reduce_while(list, 0, fn
            x, acc when x > 0 -> {:cont, acc + x}
            x, acc -> {:cont, acc - x}
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects multiple reduce_while calls without halt" do
      code = """
      defmodule Bad do
        def process(a, b) do
          x = Enum.reduce_while(a, 0, fn v, acc -> {:cont, acc + v} end)
          y = Enum.reduce_while(b, 0, fn v, acc -> {:cont, acc + v} end)
          {x, y}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end

    test "passes when callback returns bare :halt" do
      code = """
      defmodule Good do
        def search(list) do
          Enum.reduce_while(list, nil, fn
            :found, _acc -> :halt
            x, acc -> {:cont, acc + x}
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "passes unrelated code" do
      code = """
      defmodule Clean do
        def double(x), do: x * 2
      end
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    test "replaces reduce_while with reduce and unwraps {:cont, _}" do
      code = """
      Enum.reduce_while(list, 0, fn x, acc ->
        {:cont, acc + x}
      end)
      """

      result = fix(code)
      assert result =~ "Enum.reduce("
      refute result =~ "reduce_while"
      refute result =~ "{:cont,"
    end

    test "handles pipeline form" do
      code = """
      list
      |> Enum.reduce_while({0, []}, fn h, {max, acc} ->
        new_max = max(h, max)
        {:cont, {new_max, [new_max | acc]}}
      end)
      """

      result = fix(code)
      assert result =~ "Enum.reduce("
      refute result =~ "reduce_while"
      refute result =~ "{:cont,"
    end

    test "handles multi-line body with block" do
      code = """
      list
      |> Enum.reduce_while({0, []}, fn h, {current_max, acc} ->
        new_max = max(h, current_max)
        {:cont, {new_max, [new_max | acc]}}
      end)
      """

      result = fix(code)
      assert result =~ "Enum.reduce("
      assert result =~ "{new_max, [new_max | acc]}"
      refute result =~ "{:cont,"
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def process(list) do
          count = length(list)
          sum = Enum.reduce_while(list, 0, fn x, acc -> {:cont, acc + x} end)
          {count, sum}
        end
      end
      """

      result = fix(code)
      assert result =~ "length(list)"
      assert result =~ "Enum.reduce("
      assert result =~ "{count, sum}"
    end

    test "does not modify reduce_while with :halt" do
      code = """
      Enum.reduce_while(list, 0, fn x, acc ->
        if x < 0, do: {:halt, acc}, else: {:cont, acc + x}
      end)
      """

      result = fix(code)
      assert result =~ "reduce_while"
    end

    test "round-trip: fixed code produces no issues" do
      code = """
      Enum.reduce_while(list, 0, fn x, acc ->
        {:cont, acc + x}
      end)
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoReduceWhileWithoutHalt.check(ast, []) == []
    end
  end
end
