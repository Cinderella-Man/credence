defmodule Credence.Pattern.NoEnumAtMidpointAccessFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoEnumAtMidpointAccess

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoEnumAtMidpointAccess.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoEnumAtMidpointAccess, code, [])
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  describe "fix" do
    test "direct call: inserts List.to_tuple and replaces Enum.at with elem" do
      input = """
      defmodule Search do
        def find(list, low, high) do
          mid = low + div(high - low, 2)
          mid_val = Enum.at(list, mid)
          mid_val
        end
      end
      """

      expected = """
      defmodule Search do
        def find(list, low, high) do
          list_tuple = List.to_tuple(list)
          mid = low + div(high - low, 2)
          mid_val = elem(list_tuple, mid)
          mid_val
        end
      end
      """

      assert fix(input) == expected
    end

    test "piped call: replaces piped Enum.at with elem" do
      input = """
      defmodule Piped do
        def find(list, low, high) do
          mid = low + div(high - low, 2)
          list |> Enum.at(mid)
        end
      end
      """

      expected = """
      defmodule Piped do
        def find(list, low, high) do
          list_tuple = List.to_tuple(list)
          mid = low + div(high - low, 2)

          elem(
            list_tuple,
            mid
          )
        end
      end
      """

      assert fix(input) == expected
    end

    test "inline midpoint expression" do
      input = """
      defmodule Inline do
        def find(list, low, high) do
          Enum.at(list, div(low + high, 2))
        end
      end
      """

      expected = """
      defmodule Inline do
        def find(list, low, high) do
          list_tuple = List.to_tuple(list)

          elem(
            list_tuple,
            div(low + high, 2)
          )
        end
      end
      """

      assert fix(input) == expected
    end

    test "multiple lists: creates a tuple variable for each list" do
      input = """
      defmodule Multi do
        def compare(keys, values, low, high) do
          mid = low + div(high - low, 2)
          k = Enum.at(keys, mid)
          v = Enum.at(values, mid)
          {k, v}
        end
      end
      """

      expected = """
      defmodule Multi do
        def compare(keys, values, low, high) do
          keys_tuple = List.to_tuple(keys)
          values_tuple = List.to_tuple(values)
          mid = low + div(high - low, 2)
          k = elem(keys_tuple, mid)
          v = elem(values_tuple, mid)
          {k, v}
        end
      end
      """

      assert fix(input) == expected
    end

    test "anonymous function: inserts conversion at top of enclosing def" do
      input = """
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

      expected = """
      defmodule Iterative do
        def search(list, target) do
          list_tuple = List.to_tuple(list)

          Enum.reduce_while(0..100, {0, length(list) - 1}, fn _, {low, high} ->
            mid = low + div(high - low, 2)
            mid_val = elem(list_tuple, mid)

            cond do
              mid_val == target -> {:halt, {:ok, mid}}
              mid_val < target -> {:cont, {mid + 1, high}}
              true -> {:cont, {low, mid - 1}}
            end
          end)
        end
      end
      """

      assert fix(input) == expected
    end

    test "defp functions are fixed too" do
      input = """
      defmodule Private do
        defp lookup(list, low, high) do
          mid = div(low + high, 2)
          Enum.at(list, mid)
        end
      end
      """

      expected = """
      defmodule Private do
        defp lookup(list, low, high) do
          list_tuple = List.to_tuple(list)
          mid = div(low + high, 2)

          elem(
            list_tuple,
            mid
          )
        end
      end
      """

      assert fix(input) == expected
    end

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

      assert fix(code) == code
    end

    test "does not modify functions without flagged Enum.at" do
      code = """
      defmodule Safe do
        def get(list, i) do
          Enum.at(list, i)
        end
      end
      """

      assert fix(code) == code
    end

    test "only fixes the flagged function, leaves others alone" do
      input = """
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

      expected = """
      defmodule Mixed do
        def safe_get(list, i) do
          Enum.at(list, i)
        end

        def bad_search(list, low, high) do
          list_tuple = List.to_tuple(list)
          mid = div(low + high, 2)

          elem(
            list_tuple,
            mid
          )
        end
      end
      """

      assert fix(input) == expected
    end
  end

  describe "fix round-trip" do
    test "fixed code produces no check issues" do
      for code <- [
            """
            defmodule RoundTrip do
              def find(list, low, high) do
                mid = low + div(high - low, 2)
                Enum.at(list, mid)
              end
            end
            """,
            """
            defmodule RoundTrip do
              def find(list, low, high) do
                mid = div(low + high, 2)
                list |> Enum.at(mid)
              end
            end
            """,
            """
            defmodule RoundTrip do
              def find(list, low, high) do
                Enum.at(list, div(low + high, 2))
              end
            end
            """,
            """
            defmodule RoundTrip do
              def compare(keys, values, low, high) do
                mid = low + div(high - low, 2)
                k = Enum.at(keys, mid)
                v = Enum.at(values, mid)
                {k, v}
              end
            end
            """
          ] do
        assert check(fix(code)) == []
      end
    end
  end
end
