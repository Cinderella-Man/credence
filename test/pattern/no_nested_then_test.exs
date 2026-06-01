defmodule Credence.Pattern.NoNestedThenTest do
  use ExUnit.Case

  alias Credence.Pattern.NoNestedThen

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoNestedThen.check(ast, [])
  end

  describe "fires" do
    test "nested then in pipes" do
      code = """
      defmodule M do
        def compare(a, b) do
          a
          |> process()
          |> then(fn result1 ->
            b
            |> process()
            |> then(fn result2 ->
              result1 == result2
            end)
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_nested_then
    end

    test "nested then with direct calls" do
      code = """
      defmodule M do
        def compare(a, b) do
          then(a, fn x ->
            then(b, fn y ->
              x == y
            end)
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_nested_then
    end

    test "deeply nested then flags each nesting level" do
      code = """
      defmodule M do
        def combine(a, b, c) do
          then(a, fn x ->
            then(b, fn y ->
              then(c, fn z ->
                x + y + z
              end)
            end)
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end

    test "nested then with Kernel qualifier" do
      code = """
      defmodule M do
        def compare(a, b) do
          Kernel.then(a, fn x ->
            Kernel.then(b, fn y ->
              x == y
            end)
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_nested_then
    end
  end

  describe "does not fire" do
    test "single then in pipe" do
      code = """
      defmodule M do
        def transform(value) do
          value
          |> process()
          |> then(fn result ->
            result + 1
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "single direct then" do
      code = """
      defmodule M do
        def transform(value) do
          then(value, fn x -> x + 1 end)
        end
      end
      """

      assert check(code) == []
    end

    test "no then at all" do
      code = """
      defmodule M do
        def transform(value) do
          value + 1
        end
      end
      """

      assert check(code) == []
    end
  end
end
