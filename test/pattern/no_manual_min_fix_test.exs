defmodule Credence.Pattern.NoManualMinFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoManualMin

  describe "NoManualMin fix" do
    test "does not modify strict if a < b (value-kind unsafe on ties)" do
      code = """
      defmodule Good do
        def smaller(a, b), do: if(a < b, do: a, else: b)
      end
      """

      confirm_fix(fix(NoManualMin, code), code)
    end

    test "if a <= b, do: a, else: b → min(a, b)" do
      input = """
      defmodule Example do
        def smaller(a, b), do: if(a <= b, do: a, else: b)
      end
      """

      expected = """
      defmodule Example do
        def smaller(a, b), do: min(a, b)
      end
      """

      confirm_fix(fix(NoManualMin, input), expected)
    end

    test "does not modify strict if b > a (value-kind unsafe on ties)" do
      code = """
      defmodule Good do
        def smaller(a, b), do: if(b > a, do: a, else: b)
      end
      """

      confirm_fix(fix(NoManualMin, code), code)
    end

    test "if b >= a, do: a, else: b → min(a, b)" do
      input = """
      defmodule Example do
        def smaller(a, b), do: if(b >= a, do: a, else: b)
      end
      """

      expected = """
      defmodule Example do
        def smaller(a, b), do: min(a, b)
      end
      """

      confirm_fix(fix(NoManualMin, input), expected)
    end

    test "if a >= b, do: b, else: a → min(b, a)" do
      input = """
      defmodule Example do
        def smaller(a, b), do: if(a >= b, do: b, else: a)
      end
      """

      expected = """
      defmodule Example do
        def smaller(a, b), do: min(b, a)
      end
      """

      confirm_fix(fix(NoManualMin, input), expected)
    end

    test "with do/end block syntax" do
      input = """
      defmodule Example do
        def smaller(a, b) do
          if a <= b do
            a
          else
            b
          end
        end
      end
      """

      expected = """
      defmodule Example do
        def smaller(a, b) do
          min(a, b)
        end
      end
      """

      confirm_fix(fix(NoManualMin, input), expected)
    end

    test "complex expressions" do
      input = """
      defmodule Example do
        def clamp_low(value, floor) do
          if value - 1 <= floor, do: value - 1, else: floor
        end
      end
      """

      expected = """
      defmodule Example do
        def clamp_low(value, floor) do
          min(value - 1, floor)
        end
      end
      """

      confirm_fix(fix(NoManualMin, input), expected)
    end

    test "multiple instances in one module" do
      input = """
      defmodule Example do
        def f(a, b, c) do
          x = if a <= b, do: a, else: b
          y = if c >= x, do: x, else: c
          y
        end
      end
      """

      expected = """
      defmodule Example do
        def f(a, b, c) do
          x = min(a, b)
          y = min(x, c)
          y
        end
      end
      """

      confirm_fix(fix(NoManualMin, input), expected)
    end

    test "in assignment context" do
      input = """
      defmodule Example do
        def smaller(a, b) do
          result = if a <= b, do: a, else: b
          result
        end
      end
      """

      expected = """
      defmodule Example do
        def smaller(a, b) do
          result = min(a, b)
          result
        end
      end
      """

      confirm_fix(fix(NoManualMin, input), expected)
    end

    test "inside function call argument" do
      input = """
      defmodule Example do
        def run(a, b) do
          IO.puts(if a <= b, do: a, else: b)
        end
      end
      """

      expected = """
      defmodule Example do
        def run(a, b) do
          IO.puts(min(a, b))
        end
      end
      """

      confirm_fix(fix(NoManualMin, input), expected)
    end

    test "does not modify already correct code" do
      code = """
      defmodule Good do
        def smaller(a, b), do: min(a, b)
      end
      """

      confirm_fix(fix(NoManualMin, code), code)
    end

    test "does not modify max pattern" do
      code = """
      defmodule Good do
        def bigger(a, b) do
          if a > b, do: a, else: b
        end
      end
      """

      confirm_fix(fix(NoManualMin, code), code)
    end

    test "does not modify if with non-comparison condition" do
      code = """
      defmodule Good do
        def pick(flag, a, b) do
          if flag, do: a, else: b
        end
      end
      """

      confirm_fix(fix(NoManualMin, code), code)
    end

    test "does not modify if without else" do
      code = """
      defmodule Good do
        def maybe(a, b) do
          if a < b, do: a
        end
      end
      """

      confirm_fix(fix(NoManualMin, code), code)
    end

    test "does not modify if with mismatched branches" do
      code = """
      defmodule Good do
        def transform(a, b) do
          if a < b, do: a * 2, else: b
        end
      end
      """

      confirm_fix(fix(NoManualMin, code), code)
    end
  end
end
