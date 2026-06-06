defmodule Credence.Pattern.NoEagerWithIndexInReduceCheckTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoEagerWithIndexInReduce

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoEagerWithIndexInReduce.check(ast, [])
  end

  describe "check/2" do
    # --- POSITIVE CASES ---

    test "detects Enum.reduce(Enum.with_index(list), ...)" do
      code = """
      defmodule BadDirect do
        def process(list) do
          Enum.reduce(Enum.with_index(list), [], fn {val, idx}, acc ->
            [{idx, val} | acc]
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_eager_with_index_in_reduce

      assert issue.message =~ "Enum.with_index"
      assert issue.message =~ "Stream.with_index"
      assert issue.meta.line != nil
    end

    test "detects list |> Enum.with_index() |> Enum.reduce(...)" do
      code = """
      defmodule BadPiped do
        def process(list) do
          list
          |> Enum.with_index()
          |> Enum.reduce([], fn {val, idx}, acc ->
            [{idx, val} | acc]
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_eager_with_index_in_reduce
    end

    test "detects with longer pipeline before with_index" do
      code = """
      defmodule Bad do
        def process(list) do
          list
          |> Enum.filter(&(&1 > 0))
          |> Enum.with_index()
          |> Enum.reduce([], fn {val, idx}, acc -> [{idx, val} | acc] end)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "detects multiple violations in same module" do
      code = """
      defmodule Bad do
        def a(l), do: Enum.reduce(Enum.with_index(l), 0, fn {_, i}, a -> a + i end)
        def b(l), do: l |> Enum.with_index() |> Enum.reduce(0, fn {_, i}, a -> a + i end)
      end
      """

      assert length(check(code)) == 2
    end

    # --- NEGATIVE CASES ---

    test "passes Stream.with_index piped into Enum.reduce" do
      code = """
      defmodule GoodStream do
        def process(list) do
          list
          |> Stream.with_index()
          |> Enum.reduce([], fn {val, idx}, acc -> [{idx, val} | acc] end)
        end
      end
      """

      assert check(code) == []
    end

    test "passes index tracked in accumulator" do
      code = """
      defmodule GoodAccumulator do
        def process(list) do
          Enum.reduce(list, {0, []}, fn val, {idx, acc} ->
            {idx + 1, [{idx, val} | acc]}
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "passes Enum.with_index used without reduce" do
      code = """
      defmodule SafeWithIndex do
        def indexed(list) do
          Enum.with_index(list)
        end
      end
      """

      assert check(code) == []
    end

    test "passes Enum.with_index piped into Enum.map (not reduce)" do
      code = """
      defmodule SafeMap do
        def process(list) do
          list
          |> Enum.with_index()
          |> Enum.map(fn {val, idx} -> {idx, val} end)
        end
      end
      """

      assert check(code) == []
    end

    test "passes Enum.with_index piped into Enum.each" do
      code = """
      defmodule SafeEach do
        def process(list) do
          list
          |> Enum.with_index()
          |> Enum.each(fn {val, idx} -> IO.puts("\#{idx}: \#{val}") end)
        end
      end
      """

      assert check(code) == []
    end
  end
end
