defmodule Credence.Pattern.NoEnumChunkEveryForAdjacentPairsTest do
  use ExUnit.Case

  alias Credence.Pattern.NoEnumChunkEveryForAdjacentPairs

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoEnumChunkEveryForAdjacentPairs.check(ast, [])
  end

  describe "check" do
    # --- POSITIVE CASES ---

    test "flags chunk_every(2, 1, :discard) piped into Enum.reduce_while" do
      code = """
      defmodule Bad do
        def check_list(list) do
          list
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.reduce_while(:unknown, fn [a, b], acc ->
            if a < b, do: {:cont, :increasing}, else: {:halt, :neither}
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_enum_chunk_every_for_adjacent_pairs
      assert hd(issues).message =~ "chunk_every"
    end

    test "flags chunk_every(2, 1, :discard) piped into Enum.reduce" do
      code = """
      defmodule Bad do
        def pairs(list) do
          list
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.reduce([], fn [a, b], acc -> [{a, b} | acc] end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_enum_chunk_every_for_adjacent_pairs
    end

    test "flags chunk_every as direct argument to Enum.reduce_while" do
      code = """
      defmodule Bad do
        def check(list) do
          Enum.reduce_while(
            Enum.chunk_every(list, 2, 1, :discard),
            :ok,
            fn [a, b], acc -> {:cont, acc} end
          )
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_enum_chunk_every_for_adjacent_pairs
    end

    test "flags chunk_every(2, 1, :discard) within a defp helper" do
      code = """
      defmodule Bad do
        def check(list) do
          do_check(list)
        end

        defp do_check(list) do
          list
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.reduce_while(:ok, fn [a, b], acc -> {:cont, acc} end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_enum_chunk_every_for_adjacent_pairs
    end

    # --- NEGATIVE CASES ---

    test "does not flag chunk_every(2, 1, :discard) piped into Enum.map" do
      code = """
      defmodule Good do
        def pairs(list) do
          list
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.map(fn [a, b] -> a + b end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag chunk_every(2, 1, :discard) without subsequent reduce" do
      code = """
      defmodule Good do
        def chunks(list) do
          Enum.chunk_every(list, 2, 1, :discard)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag chunk_every with different chunk size" do
      code = """
      defmodule Good do
        def triples(list) do
          list
          |> Enum.chunk_every(3, 1, :discard)
          |> Enum.reduce([], fn [a, b, c], acc -> [{a, b, c} | acc] end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag chunk_every with step != 1" do
      code = """
      defmodule Good do
        def pairs(list) do
          list
          |> Enum.chunk_every(2, 2, :discard)
          |> Enum.reduce([], fn [a, b], acc -> [{a, b} | acc] end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.zip with reduce" do
      code = """
      defmodule Good do
        def check(list) do
          list
          |> Enum.zip(tl(list))
          |> Enum.reduce_while(:ok, fn {a, b}, acc -> {:cont, acc} end)
        end
      end
      """

      assert check(code) == []
    end
  end
end
