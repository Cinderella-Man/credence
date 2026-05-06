defmodule Credence.Pattern.NoListAppendInReduceTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoListAppendInReduce.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoListAppendInReduce.fix(code, [])
  end

  describe "NoListAppendInReduce check" do
    # --- POSITIVE CASES ---

    test "flags acc ++ [expr] in Enum.reduce with [] initial" do
      code = """
      defmodule Bad do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            acc ++ [item * 2]
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      issue = hd(issues)
      assert issue.rule == :no_list_append_in_reduce
      assert issue.message =~ "++"
      assert issue.meta.line != nil
    end

    test "flags piped Enum.reduce with acc ++ [expr]" do
      code = """
      defmodule Bad do
        def process(list) do
          list |> Enum.reduce([], fn item, acc ->
            acc ++ [item]
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_append_in_reduce
    end

    test "flags when ++ is last expression in multi-line lambda body" do
      code = """
      defmodule Bad do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            processed = item * 2
            acc ++ [processed]
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    # --- NEGATIVE CASES ---

    test "does not flag idiomatic prepend" do
      code = """
      defmodule Good do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            [item * 2 | acc]
          end)
          |> Enum.reverse()
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag reduce with non-empty initial accumulator" do
      code = """
      defmodule NotFixable do
        def process(list) do
          Enum.reduce(list, [0], fn item, acc ->
            acc ++ [item]
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when appending multi-element list" do
      code = """
      defmodule NotFixable do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            acc ++ [item, item + 1]
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when LHS is not the accumulator variable" do
      code = """
      defmodule NotFixable do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            other ++ [item]
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when ++ is not the return expression" do
      code = """
      defmodule NotFixable do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            result = acc ++ [item]
            Enum.uniq(result)
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag ++ outside of Enum.reduce" do
      code = """
      defmodule Safe do
        def concat(a, b), do: a ++ b
      end
      """

      assert check(code) == []
    end
  end

  describe "NoListAppendInReduce fix" do
    test "fixes standalone reduce: ++ to cons + Enum.reverse" do
      code = """
      defmodule Example do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            acc ++ [item * 2]
          end)
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "++"
      assert fixed =~ "|"
      assert fixed =~ "Enum.reverse"
    end

    test "fixes piped reduce: adds Enum.reverse stage" do
      code = """
      defmodule Example do
        def process(list) do
          list |> Enum.reduce([], fn item, acc ->
            acc ++ [item]
          end)
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "++"
      assert fixed =~ "Enum.reverse"
    end

    test "fixes multi-line lambda body (only changes last expression)" do
      code = """
      defmodule Example do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            processed = item * 2
            acc ++ [processed]
          end)
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "++"
      assert fixed =~ "processed = item * 2"
      assert fixed =~ "Enum.reverse"
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

      fixed = fix(code)
      assert fixed =~ "++"
      refute fixed =~ "Enum.reverse"
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

      fixed = fix(code)
      assert fixed =~ "++"
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

      fixed = fix(code)
      assert fixed =~ "++"
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

      fixed = fix(code)
      {:ok, ast} = Code.string_to_quoted(fixed)
      issues = Credence.Pattern.NoListAppendInReduce.check(ast, [])
      assert issues == []
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

      fixed = fix(code)
      {:ok, ast} = Code.string_to_quoted(fixed)
      issues = Credence.Pattern.NoListAppendInReduce.check(ast, [])
      assert issues == []
    end
  end
end
