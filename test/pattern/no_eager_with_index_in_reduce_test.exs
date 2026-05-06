defmodule Credence.Pattern.NoEagerWithIndexInReduceTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoEagerWithIndexInReduce.check(ast, [])
  end

  defp fix(code, opts \\ []) do
    Credence.Pattern.NoEagerWithIndexInReduce.fix(code, opts)
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

  describe "fix/2 :stream strategy" do
    test "fixes direct form: Enum.with_index → Stream.with_index" do
      code = """
      defmodule Bad do
        def process(list) do
          Enum.reduce(Enum.with_index(list), [], fn {val, idx}, acc ->
            [{idx, val} | acc]
          end)
        end
      end
      """

      result = fix(code)

      assert result =~ "Stream.with_index"
      refute result =~ "Enum.with_index"
      assert result =~ "Enum.reduce"
    end

    test "fixes pipe form: Enum.with_index → Stream.with_index" do
      code = """
      defmodule Bad do
        def process(list) do
          list
          |> Enum.with_index()
          |> Enum.reduce([], fn {val, idx}, acc -> [{idx, val} | acc] end)
        end
      end
      """

      result = fix(code)

      assert result =~ "Stream.with_index"
      refute result =~ "Enum.with_index"
    end

    test "preserves fn body unchanged" do
      code = """
      defmodule Bad do
        def process(list) do
          Enum.reduce(Enum.with_index(list), 0, fn {_val, idx}, acc ->
            acc + idx
          end)
        end
      end
      """

      result = fix(code)

      assert result =~ "acc + idx"
      assert result =~ "Stream.with_index"
    end

    test "does not touch Enum.with_index outside reduce" do
      code = """
      defmodule Fine do
        def a(list), do: Enum.with_index(list)
        def b(list), do: list |> Enum.with_index() |> Enum.map(&elem(&1, 0))
      end
      """

      result = fix(code)

      assert result =~ "Enum.with_index"
    end

    test "round-trip: fixed code has zero issues" do
      code = """
      defmodule Bad do
        def a(l), do: Enum.reduce(Enum.with_index(l), 0, fn {_, i}, a -> a + i end)
        def b(l), do: l |> Enum.with_index() |> Enum.reduce(0, fn {_, i}, a -> a + i end)
      end
      """

      fixed = fix(code)
      {:ok, ast} = Code.string_to_quoted(fixed)
      assert [] == Credence.Pattern.NoEagerWithIndexInReduce.check(ast, [])
    end
  end

  describe "fix/2 :reduce strategy — direct form" do
    test "transforms direct form into accumulator-tracked index" do
      code = """
      defmodule Bad do
        def process(list) do
          Enum.reduce(Enum.with_index(list), [], fn {val, idx}, acc ->
            [{idx, val} | acc]
          end)
        end
      end
      """

      result = fix(code, fix_strategy: :reduce)

      # Should wrap with elem(..., 1)
      assert result =~ "elem("
      # Should have {0, []} as initial accumulator
      assert result =~ "{0, []}"
      # fn should take val, {idx, acc}
      assert result =~ "val, {idx, acc}"
      # Body should be wrapped with {idx + 1, ...}
      assert result =~ "idx + 1"
      # No more Enum.with_index
      refute result =~ "Enum.with_index"
      refute result =~ "Stream.with_index"
    end

    test "produces valid Elixir" do
      code = """
      defmodule Bad do
        def process(list) do
          Enum.reduce(Enum.with_index(list), [], fn {val, idx}, acc ->
            [{idx, val} | acc]
          end)
        end
      end
      """

      result = fix(code, fix_strategy: :reduce)
      assert {:ok, _} = Code.string_to_quoted(result)
    end
  end

  describe "fix/2 :reduce strategy — pipe form" do
    test "transforms pipe form into accumulator-tracked index" do
      code = """
      defmodule Bad do
        def process(list) do
          list
          |> Enum.with_index()
          |> Enum.reduce([], fn {val, idx}, acc ->
            [{idx, val} | acc]
          end)
        end
      end
      """

      result = fix(code, fix_strategy: :reduce)

      # Should pipe into elem(1) at the end
      assert result =~ "elem(1)"
      # Should have {0, []} as initial accumulator
      assert result =~ "{0, []}"
      # fn should take val, {idx, acc}
      assert result =~ "val, {idx, acc}"
      # Body wrapped with {idx + 1, ...}
      assert result =~ "idx + 1"
      # No more with_index
      refute result =~ "with_index"
    end

    test "strips with_index from pipe, keeps upstream steps" do
      code = """
      defmodule Bad do
        def process(list) do
          list
          |> Enum.filter(&(&1 > 0))
          |> Enum.with_index()
          |> Enum.reduce(0, fn {val, idx}, acc -> acc + idx end)
        end
      end
      """

      result = fix(code, fix_strategy: :reduce)

      assert result =~ "Enum.filter"
      refute result =~ "with_index"
      assert result =~ "elem(1)"
    end

    test "produces valid Elixir" do
      code = """
      defmodule Bad do
        def process(list) do
          list
          |> Enum.with_index()
          |> Enum.reduce([], fn {val, idx}, acc -> [{idx, val} | acc] end)
        end
      end
      """

      result = fix(code, fix_strategy: :reduce)
      assert {:ok, _} = Code.string_to_quoted(result)
    end
  end

  describe "fix/2 :reduce strategy — fallback to :stream" do
    test "falls back to stream when fn has complex destructuring" do
      code = """
      defmodule Bad do
        def process(list) do
          Enum.reduce(Enum.with_index(list), [], fn {{a, b}, idx}, acc ->
            [{idx, a, b} | acc]
          end)
        end
      end
      """

      result = fix(code, fix_strategy: :reduce)

      # Can't transform {a, b} pattern → falls back to stream
      assert result =~ "Stream.with_index"
      refute result =~ "Enum.with_index"
    end
  end

  describe "fix/2 :reduce strategy — round-trips" do
    test "round-trip: direct form produces zero issues" do
      code = """
      defmodule Bad do
        def process(list) do
          Enum.reduce(Enum.with_index(list), 0, fn {_val, idx}, acc ->
            acc + idx
          end)
        end
      end
      """

      fixed = fix(code, fix_strategy: :reduce)
      {:ok, ast} = Code.string_to_quoted(fixed)
      assert [] == Credence.Pattern.NoEagerWithIndexInReduce.check(ast, [])
    end

    test "round-trip: pipe form produces zero issues" do
      code = """
      defmodule Bad do
        def process(list) do
          list
          |> Enum.with_index()
          |> Enum.reduce([], fn {val, idx}, acc -> [{idx, val} | acc] end)
        end
      end
      """

      fixed = fix(code, fix_strategy: :reduce)
      {:ok, ast} = Code.string_to_quoted(fixed)
      assert [] == Credence.Pattern.NoEagerWithIndexInReduce.check(ast, [])
    end
  end

  describe "fix/2 strategy selection" do
    test "defaults to :stream when no option given" do
      code = """
      defmodule Bad do
        def process(list) do
          Enum.reduce(Enum.with_index(list), [], fn {val, idx}, acc ->
            [{idx, val} | acc]
          end)
        end
      end
      """

      result = fix(code)

      assert result =~ "Stream.with_index"
      refute result =~ "elem("
    end

    test ":stream and :reduce produce different output" do
      code = """
      defmodule Bad do
        def process(list) do
          Enum.reduce(Enum.with_index(list), [], fn {val, idx}, acc ->
            [{idx, val} | acc]
          end)
        end
      end
      """

      stream_result = fix(code, fix_strategy: :stream)
      reduce_result = fix(code, fix_strategy: :reduce)

      refute stream_result == reduce_result
      assert stream_result =~ "Stream.with_index"
      assert reduce_result =~ "elem("
    end

    test "both strategies produce valid Elixir for same input" do
      code = """
      defmodule Bad do
        def process(list) do
          list
          |> Enum.with_index()
          |> Enum.reduce(0, fn {_val, idx}, acc -> acc + idx end)
        end
      end
      """

      stream_result = fix(code, fix_strategy: :stream)
      reduce_result = fix(code, fix_strategy: :reduce)

      assert {:ok, _} = Code.string_to_quoted(stream_result)
      assert {:ok, _} = Code.string_to_quoted(reduce_result)
    end

    test "both strategies produce zero check issues for same input" do
      code = """
      defmodule Bad do
        def a(l), do: Enum.reduce(Enum.with_index(l), 0, fn {_, i}, a -> a + i end)
      end
      """

      for strategy <- [:stream, :reduce] do
        fixed = fix(code, fix_strategy: strategy)
        {:ok, ast} = Code.string_to_quoted(fixed)

        assert [] == Credence.Pattern.NoEagerWithIndexInReduce.check(ast, []),
               "Strategy #{strategy} left issues"
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Production bug reproduction: String.graphemes preservation
  # ═══════════════════════════════════════════════════════════════
  #
  # idx=9 (length_of_longest_substring): the LLM wrote correct code
  # with `graphemes = String.graphemes(input_string)` on a separate
  # line, then `Enum.reduce(Enum.with_index(graphemes), ...)`.
  #
  # The fix should ONLY swap Enum.with_index → Stream.with_index
  # inside the reduce call. It must NOT modify the variable
  # assignment on the preceding line.
  #
  # If these tests pass but the integrated Credence.fix still strips
  # String.graphemes, the bug is in a DIFFERENT rule.

  describe "fix preserves surrounding code (production bug regression)" do
    test "does not strip String.graphemes from variable assignment" do
      code = """
      defmodule SlidingWindow do
        def length_of_longest_substring(input_string) do
          graphemes = String.graphemes(input_string)

          Enum.reduce(Enum.with_index(graphemes), %{left: 0, last_seen: %{}, max_length: 0}, fn {grapheme, current_index}, acc ->
            %{acc | max_length: max(acc.max_length, current_index)}
          end)
        end
      end
      """

      result = fix(code)

      # Must swap Enum.with_index → Stream.with_index
      assert result =~ "Stream.with_index"
      refute result =~ "Enum.with_index"

      # Must NOT strip String.graphemes from the variable assignment
      assert result =~ "String.graphemes(input_string)"
      refute result =~ "graphemes = input_string"
    end

    test "preserves String.graphemes in pipe form" do
      code = """
      defmodule SlidingWindow do
        def process(input_string) do
          graphemes = String.graphemes(input_string)

          graphemes
          |> Enum.with_index()
          |> Enum.reduce(%{max: 0}, fn {grapheme, idx}, acc ->
            %{acc | max: max(acc.max, idx)}
          end)
        end
      end
      """

      result = fix(code)

      assert result =~ "Stream.with_index"
      refute result =~ "Enum.with_index"
      assert result =~ "String.graphemes(input_string)"
    end

    test "output compiles for graphemes pattern" do
      code = """
      defmodule SlidingWindow do
        def length_of_longest_substring(input_string) do
          graphemes = String.graphemes(input_string)

          Enum.reduce(Enum.with_index(graphemes), %{left: 0, max_length: 0}, fn {grapheme, current_index}, acc ->
            left_start = acc.left
            current_length = current_index - left_start + 1
            max_len = max(current_length, acc.max_length)
            %{left: left_start, max_length: max_len}
          end)
          |> Map.get(:max_length)
        end
      end
      """

      result = fix(code)
      assert {:ok, _ast} = Code.string_to_quoted(result)
    end
  end
end
