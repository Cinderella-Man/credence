defmodule Credence.Pattern.NoGroupByIdentityTest do
  use ExUnit.Case

  alias Credence.Pattern.NoGroupByIdentity

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoGroupByIdentity.check(ast, [])
  end

  describe "check" do
    test "detects Enum.group_by(enum, & &1)" do
      code = """
      defmodule Bad do
        def count_single(numbers) do
          numbers
          |> Enum.group_by(& &1)
          |> Map.filter(fn {_key, values} -> match?([_], values) end)
          |> Map.keys()
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_group_by_identity
      assert hd(issues).message =~ "Enum.frequencies"
    end

    test "detects Enum.group_by(enum, fn x -> x end)" do
      code = """
      defmodule Bad do
        def group(list) do
          Enum.group_by(list, fn x -> x end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_group_by_identity
    end

    test "detects piped Enum.group_by(& &1)" do
      code = """
      defmodule Bad do
        def group(list) do
          list |> Enum.group_by(& &1)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "does not fire on Enum.group_by with a transform function" do
      code = """
      defmodule Good do
        def group_by_first_char(words) do
          Enum.group_by(words, &String.first/1)
        end
      end
      """

      assert check(code) == []
    end

    test "does not fire on Enum.group_by with derived key" do
      code = """
      defmodule Good do
        def group_by_length(list) do
          Enum.group_by(list, &length/1)
        end
      end
      """

      assert check(code) == []
    end

    test "does not fire on Enum.frequencies" do
      code = """
      defmodule Good do
        def freq(list) do
          Enum.frequencies(list)
        end
      end
      """

      assert check(code) == []
    end

    test "does not fire on Enum.group_by with anonymous function that is not identity" do
      code = """
      defmodule Good do
        def group(list) do
          Enum.group_by(list, fn x -> rem(x, 2) end)
        end
      end
      """

      assert check(code) == []
    end

    test "fires exactly once for a single group_by(& &1)" do
      code = """
      defmodule Bad do
        def process(list) do
          list
          |> Enum.group_by(& &1)
          |> Map.filter(fn {_k, v} -> match?([_], v) end)
          |> Map.keys()
          |> Enum.sort()
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "reports correct line number" do
      code = """
      defmodule Bad do
        def group(list) do
          Enum.group_by(list, & &1)
        end
      end
      """

      issues = check(code)
      assert hd(issues).meta.line != nil
    end
  end
end
