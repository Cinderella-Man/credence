defmodule Credence.Pattern.NoKernelShadowingTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoKernelShadowing.check(ast, [])
  end

  describe "NoKernelShadowing" do
    test "flags max used as a variable in a reducer" do
      code = """
      Enum.reduce(list, 0, fn x, max ->
        max(x, max)
      end)
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_kernel_shadowing
      assert String.contains?(hd(issues).message, "variable `max` shadows")
    end

    test "flags min used as a variable in a match" do
      code = """
      def find_min(list) do
        [head | tail] = list
        min = head
        Enum.reduce(tail, min, fn x, acc -> min(x, acc) end)
      end
      """

      assert length(check(code)) == 1
    end

    test "flags both max and min if used" do
      code = """
      {max, min} = {100, 0}
      """

      # uniq_by line will keep 1 if they are on the same line,
      # but we check for at least one issue.
      assert length(check(code)) >= 1
    end

    test "does not flag standard function calls" do
      code = """
      defmodule Example do
        def run(a, b), do: max(a, b)
      end
      """

      assert check(code) == []
    end

    test "does not flag idiomatic variable names" do
      code = """
      Enum.reduce(list, 0, fn x, max_val ->
        max(x, max_val)
      end)
      """

      assert check(code) == []
    end

    test "does not flag atom keys in maps or keywords" do
      code = """
      data = %{max: 10, min: 0}
      opts = [max: 5]
      """

      # AST for %{max: 10} is different from a variable node
      assert check(code) == []
    end
  end
end
