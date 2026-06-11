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
          |> then(&(&1 == String.reverse(&1)))
        end
      end
      """

      assert fix(PreferThenOverCaptureInvocation, input) == expected
    end

    test "simple capture with &1 + 1" do
      input = """
      x |> (&(&1 + 1)).()
      """

      expected = """
      x |> then(&(&1 + 1))
      """

      assert fix(PreferThenOverCaptureInvocation, input) == expected
    end

    test "bare &1 capture" do
      input = """
      x |> (& &1).()
      """

      expected = """
      x |> then(& &1)
      """

      assert fix(PreferThenOverCaptureInvocation, input) == expected
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

      assert fix(PreferThenOverCaptureInvocation, code) == code
    end

    test "capture with arity > 1 (uses &2)" do
      code = """
      x |> (&(&1 + &2)).()
      """

      assert fix(PreferThenOverCaptureInvocation, code) == code
    end
  end
end
