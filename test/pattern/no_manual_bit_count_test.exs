defmodule Credence.Pattern.NoManualBitCountTest do
  use ExUnit.Case, async: true

  alias Credence.Pattern.NoManualBitCount

  describe "check/2" do
    test "flags hand-rolled bit-counting loop with Bitwise module calls" do
      code = """
      defmodule TestModule do
        def bit_count(0), do: 0

        def bit_count(number) when is_integer(number) and number > 0 do
          count_bits(number, 0)
        end

        defp count_bits(0, acc), do: acc

        defp count_bits(number, acc) do
          count_bits(Bitwise.bsr(number, 1), acc + Bitwise.band(number, 1))
        end
      end
      """

      ast = Sourceror.parse_string!(code)
      issues = NoManualBitCount.check(ast, [])

      assert length(issues) >= 1
      assert Enum.any?(issues, &(&1.rule == :no_manual_bit_count))
    end

    test "flags hand-rolled bit-counting loop with operator syntax" do
      code = """
      defmodule TestModule do
        import Bitwise

        def bit_count(0), do: 0

        def bit_count(number) when is_integer(number) and number > 0 do
          count_bits(number, 0)
        end

        defp count_bits(0, acc), do: acc

        defp count_bits(number, acc) do
          count_bits(number >>> 1, acc + (number &&& 1))
        end
      end
      """

      ast = Sourceror.parse_string!(code)
      issues = NoManualBitCount.check(ast, [])

      assert length(issues) >= 1
      assert Enum.any?(issues, &(&1.rule == :no_manual_bit_count))
    end

    test "does not flag Integer.digits approach" do
      code = """
      defmodule TestModule do
        def bit_count(number) when is_integer(number) and number >= 0 do
          number
          |> Integer.digits(2)
          |> Enum.sum()
        end
      end
      """

      ast = Sourceror.parse_string!(code)
      issues = NoManualBitCount.check(ast, [])

      refute Enum.any?(issues, &(&1.rule == :no_manual_bit_count))
    end

    test "does not flag non-recursive use of Bitwise" do
      code = """
      defmodule TestModule do
        def shift_right(number) do
          Bitwise.bsr(number, 1)
        end
      end
      """

      ast = Sourceror.parse_string!(code)
      issues = NoManualBitCount.check(ast, [])

      refute Enum.any?(issues, &(&1.rule == :no_manual_bit_count))
    end

    test "does not flag recursive Bitwise without bsr+band combination" do
      code = """
      defmodule TestModule do
        defp shift_loop(0, acc), do: acc

        defp shift_loop(number, acc) do
          shift_loop(Bitwise.bsr(number, 1), acc)
        end
      end
      """

      ast = Sourceror.parse_string!(code)
      issues = NoManualBitCount.check(ast, [])

      refute Enum.any?(issues, &(&1.rule == :no_manual_bit_count))
    end

    test "fix_patches returns empty list" do
      code = """
      defmodule TestModule do
        defp count_bits(0, acc), do: acc

        defp count_bits(number, acc) do
          count_bits(Bitwise.bsr(number, 1), acc + Bitwise.band(number, 1))
        end
      end
      """

      ast = Sourceror.parse_string!(code)
      assert NoManualBitCount.fix_patches(ast, []) == []
    end
  end
end
