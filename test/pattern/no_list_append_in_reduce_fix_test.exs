defmodule Credence.Pattern.NoListAppendInReduceFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoListAppendInReduce

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoListAppendInReduce.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoListAppendInReduce, code, [])
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  describe "NoListAppendInReduce fix" do
    test "fixes standalone reduce: ++ to cons + Enum.reverse" do
      input = """
      defmodule Example do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            acc ++ [item * 2]
          end)
        end
      end
      """

      expected = """
      defmodule Example do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            [item * 2 | acc]
          end)
          |> Enum.reverse()
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes piped reduce: adds Enum.reverse stage" do
      input = """
      defmodule Example do
        def process(list) do
          list |> Enum.reduce([], fn item, acc ->
            acc ++ [item]
          end)
        end
      end
      """

      expected = """
      defmodule Example do
        def process(list) do
          list
          |> Enum.reduce([], fn item, acc ->
            [item | acc]
          end)
          |> Enum.reverse()
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes multi-line lambda body (only changes last expression)" do
      input = """
      defmodule Example do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            processed = item * 2
            acc ++ [processed]
          end)
        end
      end
      """

      expected = """
      defmodule Example do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            processed = item * 2
            [processed | acc]
          end)
          |> Enum.reverse()
        end
      end
      """

      assert fix(input) == expected
    end

    test "does not modify reduce with non-empty initial" do
      code = """
      defmodule Example do
        def process(list) do
          Enum.reduce(list, [0], fn item, acc ->
            acc ++ [item]
          end)
        end
      end
      """

      assert fix(code) == code
    end

    test "does not modify when LHS is not the accumulator" do
      code = """
      defmodule Example do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            other ++ [item]
          end)
        end
      end
      """

      assert fix(code) == code
    end

    test "does not modify when appending multi-element list" do
      code = """
      defmodule Example do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            acc ++ [item, item + 1]
          end)
        end
      end
      """

      assert fix(code) == code
    end

    test "fixed code has no remaining issues" do
      code = """
      defmodule Example do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            acc ++ [item * 2]
          end)
        end
      end
      """

      assert check(fix(code)) == []
    end

    test "fixed piped code has no remaining issues" do
      code = """
      defmodule Example do
        def process(list) do
          list |> Enum.reduce([], fn item, acc ->
            acc ++ [item]
          end)
        end
      end
      """

      assert check(fix(code)) == []
    end
  end
end
