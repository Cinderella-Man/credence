defmodule Credence.Pattern.NoReduceWhileWithoutHaltCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoReduceWhileWithoutHalt

  describe "fires" do
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

      issues = check(NoReduceWhileWithoutHalt, code)
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

      issues = check(NoReduceWhileWithoutHalt, code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_reduce_while_without_halt
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

      issues = check(NoReduceWhileWithoutHalt, code)
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

      issues = check(NoReduceWhileWithoutHalt, code)
      assert length(issues) == 2
    end
  end

  describe "no issue" do
    test "passes code that uses Enum.reduce (not reduce_while)" do
      code = """
      defmodule Good do
        def total(list) do
          Enum.reduce(list, 0, fn x, acc -> acc + x end)
        end
      end
      """

      assert check(NoReduceWhileWithoutHalt, code) == []
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

      assert check(NoReduceWhileWithoutHalt, code) == []
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

      assert check(NoReduceWhileWithoutHalt, code) == []
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

      assert check(NoReduceWhileWithoutHalt, code) == []
    end

    # Deliberately skipped: the last expression is a `case`, not a literal
    # `{:cont, _}`. The rule only fires when every clause *literally* returns a
    # cont-tuple, so rewriting would require descending into the branches.
    # Skipping keeps the safe-core narrow.
    test "passes when the cont is buried inside a case (not the literal last expr)" do
      code = """
      defmodule Skipped do
        def process(list) do
          Enum.reduce_while(list, 0, fn x, acc ->
            case x do
              0 -> {:cont, acc}
              _ -> {:cont, acc + x}
            end
          end)
        end
      end
      """

      assert check(NoReduceWhileWithoutHalt, code) == []
    end

    # Deliberately skipped: an `if` whose branches both return cont is not a
    # literal `{:cont, _}` last expression, so the rule conservatively ignores it.
    test "passes when the cont is buried inside an if (not the literal last expr)" do
      code = """
      defmodule Skipped do
        def process(list) do
          Enum.reduce_while(list, 0, fn x, acc ->
            if x > 0, do: {:cont, acc + x}, else: {:cont, acc - x}
          end)
        end
      end
      """

      assert check(NoReduceWhileWithoutHalt, code) == []
    end

    test "passes unrelated code" do
      code = """
      defmodule Clean do
        def double(x), do: x * 2
      end
      """

      assert check(NoReduceWhileWithoutHalt, code) == []
    end
  end
end
