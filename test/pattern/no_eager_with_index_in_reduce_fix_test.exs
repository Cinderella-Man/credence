defmodule Credence.Pattern.NoEagerWithIndexInReduceFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoEagerWithIndexInReduce

  describe "fix/2 :stream strategy" do
    test "fixes direct form: Enum.with_index → Stream.with_index" do
      input = """
      defmodule Bad do
        def process(list) do
          Enum.reduce(Enum.with_index(list), [], fn {val, idx}, acc ->
            [{idx, val} | acc]
          end)
        end
      end
      """

      expected = """
      defmodule Bad do
        def process(list) do
          Enum.reduce(Stream.with_index(list), [], fn {val, idx}, acc ->
            [{idx, val} | acc]
          end)
        end
      end
      """

      assert fix(NoEagerWithIndexInReduce, input) == expected
    end

    test "fixes pipe form: Enum.with_index → Stream.with_index" do
      input = """
      defmodule Bad do
        def process(list) do
          list
          |> Enum.with_index()
          |> Enum.reduce([], fn {val, idx}, acc -> [{idx, val} | acc] end)
        end
      end
      """

      expected = """
      defmodule Bad do
        def process(list) do
          list
          |> Stream.with_index()
          |> Enum.reduce([], fn {val, idx}, acc -> [{idx, val} | acc] end)
        end
      end
      """

      assert fix(NoEagerWithIndexInReduce, input) == expected
    end

    test "preserves fn body unchanged" do
      input = """
      defmodule Bad do
        def process(list) do
          Enum.reduce(Enum.with_index(list), 0, fn {_val, idx}, acc ->
            acc + idx
          end)
        end
      end
      """

      expected = """
      defmodule Bad do
        def process(list) do
          Enum.reduce(Stream.with_index(list), 0, fn {_val, idx}, acc ->
            acc + idx
          end)
        end
      end
      """

      assert fix(NoEagerWithIndexInReduce, input) == expected
    end

    test "does not touch Enum.with_index outside reduce" do
      code = """
      defmodule Fine do
        def a(list), do: Enum.with_index(list)
        def b(list), do: list |> Enum.with_index() |> Enum.map(&elem(&1, 0))
      end
      """

      assert fix(NoEagerWithIndexInReduce, code) == code
    end

    test "round-trip: fixed code has zero issues" do
      code = """
      defmodule Bad do
        def a(l), do: Enum.reduce(Enum.with_index(l), 0, fn {_, i}, a -> a + i end)
        def b(l), do: l |> Enum.with_index() |> Enum.reduce(0, fn {_, i}, a -> a + i end)
      end
      """

      assert check(NoEagerWithIndexInReduce, fix(NoEagerWithIndexInReduce, code)) == []
    end
  end

  describe "fix/2 :reduce strategy — direct form" do
    test "transforms direct form into accumulator-tracked index" do
      input = """
      defmodule Bad do
        def process(list) do
          Enum.reduce(Enum.with_index(list), [], fn {val, idx}, acc ->
            [{idx, val} | acc]
          end)
        end
      end
      """

      expected = """
      defmodule Bad do
        def process(list) do
          elem(
            Enum.reduce(list, {0, []}, fn val, {idx, acc} ->
              {idx + 1, [{idx, val} | acc]}
            end),
            1
          )
        end
      end
      """

      assert fix(NoEagerWithIndexInReduce, input, fix_strategy: :reduce) == expected
    end
  end

  describe "fix/2 :reduce strategy — pipe form" do
    test "transforms pipe form into accumulator-tracked index" do
      input = """
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

      expected = """
      defmodule Bad do
        def process(list) do
          list
          |> Enum.reduce({0, []}, fn val, {idx, acc} ->
            {idx + 1, [{idx, val} | acc]}
          end)
          |> elem(1)
        end
      end
      """

      assert fix(NoEagerWithIndexInReduce, input, fix_strategy: :reduce) == expected
    end

    test "strips with_index from pipe, keeps upstream steps" do
      input = """
      defmodule Bad do
        def process(list) do
          list
          |> Enum.filter(&(&1 > 0))
          |> Enum.with_index()
          |> Enum.reduce(0, fn {val, idx}, acc -> acc + idx end)
        end
      end
      """

      expected = """
      defmodule Bad do
        def process(list) do
          list
          |> Enum.filter(&(&1 > 0))
          |> Enum.reduce({0, 0}, fn val, {idx, acc} -> {idx + 1, acc + idx} end)
          |> elem(1)
        end
      end
      """

      assert fix(NoEagerWithIndexInReduce, input, fix_strategy: :reduce) == expected
    end
  end

  describe "fix/2 :reduce strategy — fallback to :stream" do
    test "falls back to stream when fn has complex destructuring" do
      input = """
      defmodule Bad do
        def process(list) do
          Enum.reduce(Enum.with_index(list), [], fn {{a, b}, idx}, acc ->
            [{idx, a, b} | acc]
          end)
        end
      end
      """

      expected = """
      defmodule Bad do
        def process(list) do
          Enum.reduce(Stream.with_index(list), [], fn {{a, b}, idx}, acc ->
            [{idx, a, b} | acc]
          end)
        end
      end
      """

      assert fix(NoEagerWithIndexInReduce, input, fix_strategy: :reduce) == expected
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

      assert check(
               NoEagerWithIndexInReduce,
               fix(NoEagerWithIndexInReduce, code, fix_strategy: :reduce)
             ) == []
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

      assert check(
               NoEagerWithIndexInReduce,
               fix(NoEagerWithIndexInReduce, code, fix_strategy: :reduce)
             ) == []
    end
  end

  describe "fix/2 strategy selection" do
    test "defaults to :stream when no option given" do
      input = """
      defmodule Bad do
        def process(list) do
          Enum.reduce(Enum.with_index(list), [], fn {val, idx}, acc ->
            [{idx, val} | acc]
          end)
        end
      end
      """

      expected = """
      defmodule Bad do
        def process(list) do
          Enum.reduce(Stream.with_index(list), [], fn {val, idx}, acc ->
            [{idx, val} | acc]
          end)
        end
      end
      """

      assert fix(NoEagerWithIndexInReduce, input) == expected
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

      refute fix(NoEagerWithIndexInReduce, code, fix_strategy: :stream) ==
               fix(NoEagerWithIndexInReduce, code, fix_strategy: :reduce)
    end

    test "both strategies produce zero check issues for same input" do
      code = """
      defmodule Bad do
        def a(l), do: Enum.reduce(Enum.with_index(l), 0, fn {_, i}, a -> a + i end)
      end
      """

      for strategy <- [:stream, :reduce] do
        assert check(
                 NoEagerWithIndexInReduce,
                 fix(NoEagerWithIndexInReduce, code, fix_strategy: strategy)
               ) == [],
               "Strategy #{strategy} left issues"
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Production bug reproduction: String.graphemes preservation
  # ═══════════════════════════════════════════════════════════════

  describe "fix preserves surrounding code (production bug regression)" do
    test "does not strip String.graphemes from variable assignment" do
      input = """
      defmodule SlidingWindow do
        def length_of_longest_substring(input_string) do
          graphemes = String.graphemes(input_string)

          Enum.reduce(Enum.with_index(graphemes), %{left: 0, last_seen: %{}, max_length: 0}, fn {grapheme, current_index}, acc ->
            %{acc | max_length: max(acc.max_length, current_index)}
          end)
        end
      end
      """

      expected = """
      defmodule SlidingWindow do
        def length_of_longest_substring(input_string) do
          graphemes = String.graphemes(input_string)

          Enum.reduce(Stream.with_index(graphemes), %{left: 0, last_seen: %{}, max_length: 0}, fn {grapheme,
                                                                                                   current_index},
                                                                                                  acc ->
            %{acc | max_length: max(acc.max_length, current_index)}
          end)
        end
      end
      """

      assert fix(NoEagerWithIndexInReduce, input) == expected
    end

    test "preserves String.graphemes in pipe form" do
      input = """
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

      expected = """
      defmodule SlidingWindow do
        def process(input_string) do
          graphemes = String.graphemes(input_string)

          graphemes
          |> Stream.with_index()
          |> Enum.reduce(%{max: 0}, fn {grapheme, idx}, acc ->
            %{acc | max: max(acc.max, idx)}
          end)
        end
      end
      """

      assert fix(NoEagerWithIndexInReduce, input) == expected
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

      assert valid_syntax?(fix(NoEagerWithIndexInReduce, code))
    end
  end
end
