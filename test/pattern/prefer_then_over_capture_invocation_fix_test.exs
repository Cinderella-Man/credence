defmodule Credence.Pattern.PreferThenOverCaptureInvocationFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferThenOverCaptureInvocation

  describe "rewrites |> (&body).() to |> then(&body)" do
    test "palindrome example" do
      input = """
      defmodule Example do
        def palindrome?(number) do
          number
          |> Integer.to_string()
          |> (&(&1 == String.reverse(&1))).()
        end
      end
      """

      expected = """
      defmodule Example do
        def palindrome?(number) do
          number
          |> Integer.to_string()
          |> Kernel.then(&(&1 == String.reverse(&1)))
        end
      end
      """

      confirm_fix(fix(PreferThenOverCaptureInvocation, input), expected)
    end

    test "simple capture with &1 + 1" do
      input = "x |> (&(&1 + 1)).()"

      expected = "x |> Kernel.then(&(&1 + 1))"

      confirm_fix(fix(PreferThenOverCaptureInvocation, input), expected)
    end

    test "bare &1 capture" do
      input = "x |> (& &1).()"

      expected = "x |> Kernel.then(& &1)"

      confirm_fix(fix(PreferThenOverCaptureInvocation, input), expected)
    end

    test "two captures in a chain each get their own patch" do
      input = "x |> (&(&1 + 1)).() |> (&(&1 * 2)).()"

      expected = "x |> Kernel.then(&(&1 + 1)) |> Kernel.then(&(&1 * 2))"

      confirm_fix(fix(PreferThenOverCaptureInvocation, input), expected)
    end

    test "qualifies Kernel.then/2 so a local then/2 cannot capture the pipeline" do
      input = """
      defmodule PreferThenLocalShadowRegression do
        import Kernel, except: [then: 2]
        def then(value, fun), do: {:local, value, fun}
        def run, do: 1 |> (&(&1 + 1)).()
        if run() != 2, do: raise("pipeline called local then/2")
      end
      """

      expected = """
      defmodule PreferThenLocalShadowRegression do
        import Kernel, except: [then: 2]
        def then(value, fun), do: {:local, value, fun}
        def run, do: 1 |> Kernel.then(&(&1 + 1))
        if run() != 2, do: raise("pipeline called local then/2")
      end
      """

      emitted = fix(PreferThenOverCaptureInvocation, input)
      confirm_fix(emitted, expected)

      assert Credence.RuleHelpers.compile_and_capture(emitted) ==
               Credence.RuleHelpers.compile_and_capture(expected)
    end

    test "includes whitespace between the opening parenthesis and capture in the patch" do
      input = "x |> (  &(&1 + 1)).()"
      expected = "x |> Kernel.then(&(&1 + 1))"

      confirm_fix(fix(PreferThenOverCaptureInvocation, input), expected)
    end
  end

  describe "leaves untouched" do
    test "code already using then/2" do
      code = """
      defmodule Good do
        def palindrome?(number) do
          number
          |> Integer.to_string()
          |> then(&(&1 == String.reverse(&1)))
        end
      end
      """

      confirm_fix(fix(PreferThenOverCaptureInvocation, code), code)
    end

    test "capture with arity > 1 (uses &2)" do
      code = "x |> (&(&1 + &2)).()"

      confirm_fix(fix(PreferThenOverCaptureInvocation, code), code)
    end
  end
end
