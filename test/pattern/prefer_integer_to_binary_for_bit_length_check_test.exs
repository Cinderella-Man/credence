defmodule Credence.Pattern.PreferIntegerToBinaryForBitLengthCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferIntegerToBinaryForBitLength

  # ═══════════════════════════════════════════════════════════════════
  # FLAGS — the anti-pattern
  # ═══════════════════════════════════════════════════════════════════

  describe "flags the anti-pattern" do
    test "standalone expression" do
      assert flagged?(PreferIntegerToBinaryForBitLength, "floor(:math.log(n) / :math.log(2)) + 1")
    end

    test "in function body with positive guard" do
      code = """
      defmodule Solution do
        def num_of_bits(n) when n > 0 do
          floor(:math.log(n) / :math.log(2)) + 1
        end
      end
      """

      assert flagged?(PreferIntegerToBinaryForBitLength, code)
    end

    test "different variable name" do
      assert flagged?(PreferIntegerToBinaryForBitLength, "floor(:math.log(x) / :math.log(2)) + 1")
    end

    test "in full module with doc and spec" do
      code = """
      defmodule Solution do
        @doc \"\"\"
        Returns the number of bits required to represent a non-negative integer.
        For 0, returns 0.
        \"\"\"
        @spec num_of_bits(non_neg_integer()) :: non_neg_integer()
        def num_of_bits(0), do: 0

        def num_of_bits(n) when n > 0 do
          floor(:math.log(n) / :math.log(2)) + 1
        end
      end
      """

      assert flagged?(PreferIntegerToBinaryForBitLength, code)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # CLEAN — not the anti-pattern
  # ═══════════════════════════════════════════════════════════════════

  describe "leaves good code alone" do
    test ":math.log without the full pattern" do
      assert clean?(PreferIntegerToBinaryForBitLength, ":math.log(n)")
    end

    test "floor of non-log expression" do
      assert clean?(PreferIntegerToBinaryForBitLength, "floor(n / 2)")
    end

    test "already-idiomatic integer_to_binary" do
      assert clean?(
               PreferIntegerToBinaryForBitLength,
               "n |> :erlang.integer_to_binary(2) |> String.length()"
             )
    end

    test "different log base (10)" do
      assert clean?(PreferIntegerToBinaryForBitLength, "floor(:math.log(n) / :math.log(10)) + 1")
    end

    test "addition of 2 instead of 1" do
      assert clean?(PreferIntegerToBinaryForBitLength, "floor(:math.log(n) / :math.log(2)) + 2")
    end

    test "no floor wrapper" do
      assert clean?(PreferIntegerToBinaryForBitLength, ":math.log(n) / :math.log(2) + 1")
    end

    test ":math.log(2) in numerator only" do
      assert clean?(PreferIntegerToBinaryForBitLength, "floor(:math.log(2) / :math.log(n)) + 1")
    end

    test "Integer.to_string base 2" do
      assert clean?(PreferIntegerToBinaryForBitLength, "Integer.to_string(n, 2)")
    end
  end
end
