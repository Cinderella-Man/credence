defmodule Credence.Syntax.NoSpecDoBlockFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoSpecDoBlock

  defp analyze(code), do: NoSpecDoBlock.analyze(code)
  defp fix(code), do: NoSpecDoBlock.fix(code)

  test "fixes the syntax error" do
    input = """
    defmodule Solution do
      @spec do
        def my_sqrt(number) when number >= 0 do
          guess = number / 2.0
          sqrt_iterate(number, guess)
        end
      end

      defp sqrt_iterate(number, guess) do
        next = (guess + number / guess) / 2.0
        if abs(next - guess) < 1.0e-7 do
          next
        else
          sqrt_iterate(number, next)
        end
      end
    end
    """

    expected = """
    defmodule Solution do
      def my_sqrt(number) when number >= 0 do
        guess = number / 2.0
        sqrt_iterate(number, guess)
      end

      defp sqrt_iterate(number, guess) do
        next = (guess + number / guess) / 2.0
        if abs(next - guess) < 1.0e-7 do
          next
        else
          sqrt_iterate(number, next)
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(
             fix("""
             defmodule Solution do
               @spec do
                 def my_sqrt(number) when number >= 0 do
                   guess = number / 2.0
                   sqrt_iterate(number, guess)
                 end
               end

               defp sqrt_iterate(number, guess) do
                 next = (guess + number / guess) / 2.0
                 if abs(next - guess) < 1.0e-7 do
                   next
                 else
                   sqrt_iterate(number, next)
                 end
               end
             end
             """)
           ) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             defmodule Solution do
               @spec do
                 def my_sqrt(number) when number >= 0 do
                   guess = number / 2.0
                   sqrt_iterate(number, guess)
                 end
               end

               defp sqrt_iterate(number, guess) do
                 next = (guess + number / guess) / 2.0
                 if abs(next - guess) < 1.0e-7 do
                   next
                 else
                   sqrt_iterate(number, next)
                 end
               end
             end
             """)
           )
  end

  test "handles nested do/end inside the block" do
    input = """
    defmodule Solution do
      @spec do
        def my_fun do
          if true do
            :ok
          end
        end
      end
    end
    """

    expected = """
    defmodule Solution do
      def my_fun do
        if true do
          :ok
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "converts @spec do with type spec to @spec" do
    input = """
    defmodule Solution do
      @spec do
        def find_majority_element(list) :: integer()
      end

      def find_majority_element(list) do
        -1
      end
    end
    """

    expected = """
    defmodule Solution do
      @spec find_majority_element(list) :: integer()

      def find_majority_element(list) do
        -1
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed type-spec output no longer flags" do
    assert analyze(
             fix("""
             defmodule Solution do
               @spec do
                 def find_majority_element(list) :: integer()
               end

               def find_majority_element(list) do
                 -1
               end
             end
             """)
           ) == []
  end

  test "fixed type-spec output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             defmodule Solution do
               @spec do
                 def find_majority_element(list) :: integer()
               end

               def find_majority_element(list) do
                 -1
               end
             end
             """)
           )
  end

  test "leaves already-clean source unchanged" do
    input = """
    defmodule Solution do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input), input)
  end

  test "leaves valid @spec unchanged" do
    input = """
    defmodule Solution do
      @spec my_sqrt(number) :: float()
      def my_sqrt(number) when number >= 0 do
        number
      end
    end
    """

    confirm_fix(fix(input), input)
  end
end
