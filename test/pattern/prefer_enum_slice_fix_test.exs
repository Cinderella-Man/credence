defmodule Credence.Pattern.PreferEnumSliceFixTest do
  use ExUnit.Case

  alias Credence.Pattern.PreferEnumSlice

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    PreferEnumSlice.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(PreferEnumSlice, code, [])
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  describe "fix" do
    test "fixes Enum.drop |> Enum.take pipeline to Enum.slice" do
      input = """
      defmodule Example do
        def extract(graphemes, start, len) do
          graphemes
          |> Enum.drop(2)
          |> Enum.take(5)
        end
      end
      """

      expected = """
      defmodule Example do
        def extract(graphemes, start, len) do
          graphemes
          |> Enum.slice(2, 5)
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes nested Enum.take(Enum.drop(...)) to Enum.slice" do
      input = """
      defmodule Example do
        def extract(list, start, len) do
          Enum.take(Enum.drop(list, 2), 5)
        end
      end
      """

      expected = """
      defmodule Example do
        def extract(list, start, len) do
          Enum.slice(list, 2, 5)
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes single pipe Enum.drop |> Enum.take to Enum.slice" do
      input = """
      defmodule Example do
        def extract(list, start, len) do
          Enum.drop(list, 2) |> Enum.take(5)
        end
      end
      """

      expected = """
      defmodule Example do
        def extract(list, start, len) do
          Enum.slice(list, 2, 5)
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes pipeline with preceding steps" do
      input = """
      defmodule Example do
        def process(list) do
          list
          |> Enum.map(&(&1 * 2))
          |> Enum.filter(&(&1 > 10))
          |> Enum.drop(5)
          |> Enum.take(3)
        end
      end
      """

      expected = """
      defmodule Example do
        def process(list) do
          list
          |> Enum.map(&(&1 * 2))
          |> Enum.filter(&(&1 > 10))
          |> Enum.slice(5, 3)
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes multiple occurrences in the same file" do
      input = """
      defmodule Example do
        def process(list) do
          a = Enum.drop(list, 0) |> Enum.take(5)
          b = Enum.drop(list, 3) |> Enum.take(10)
          {a, b}
        end
      end
      """

      expected = """
      defmodule Example do
        def process(list) do
          a = Enum.slice(list, 0, 5)
          b = Enum.slice(list, 3, 10)
          {a, b}
        end
      end
      """

      assert fix(input) == expected
    end

    test "fix inside anonymous function" do
      input = """
      Enum.map(list, fn x ->
        x
        |> Enum.drop(2)
        |> Enum.take(5)
      end)
      """

      expected = """
      Enum.map(list, fn x ->
        x
        |> Enum.slice(2, 5)
      end)
      """

      assert fix(input) == expected
    end

    test "does not modify non-literal (field-access) amounts — could be negative" do
      code = """
      defmodule Example do
        def extract(list, config) do
          Enum.take(Enum.drop(list, config.start), config.length)
        end
      end
      """

      assert fix(code) == code
    end

    test "does not modify code without the pattern" do
      code = """
      defmodule GoodSlice do
        def extract(list, start, len) do
          list
          |> Enum.slice(start, len)
        end
      end
      """

      assert fix(code) == code
    end

    test "does not modify reversed order" do
      code = """
      defmodule ReversedOrder do
        def extract(list) do
          list
          |> Enum.take(10)
          |> Enum.drop(2)
        end
      end
      """

      assert fix(code) == code
    end

    test "does not modify Stream" do
      code = """
      defmodule ValidStream do
        def extract(list) do
          list
          |> Stream.drop(5)
          |> Stream.take(5)
        end
      end
      """

      assert fix(code) == code
    end

    test "fix is idempotent" do
      input = """
      defmodule Example do
        def extract(list, start, len) do
          list
          |> Enum.drop(2)
          |> Enum.take(5)
        end
      end
      """

      first_pass = fix(input)
      second_pass = fix(first_pass)
      assert first_pass == second_pass
    end

    test "fixed pipeline passes check" do
      input = """
      defmodule Example do
        def extract(list, start, len) do
          list
          |> Enum.drop(2)
          |> Enum.take(5)
        end
      end
      """

      assert check(fix(input)) == []
    end

    test "fixed nested call passes check" do
      input = """
      defmodule Example do
        def extract(list, start, len) do
          Enum.take(Enum.drop(list, 2), 5)
        end
      end
      """

      assert check(fix(input)) == []
    end

    test "fixed single pipe passes check" do
      input = """
      defmodule Example do
        def extract(list, start, len) do
          Enum.drop(list, 2) |> Enum.take(5)
        end
      end
      """

      assert check(fix(input)) == []
    end
  end
end
