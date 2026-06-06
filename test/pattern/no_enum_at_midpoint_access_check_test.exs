defmodule Credence.Pattern.NoEnumAtMidpointAccessCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoEnumAtMidpointAccess

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoEnumAtMidpointAccess.check(ast, [])
  end

  describe "detects non-recursive midpoint access patterns" do
    test "flags Enum.at with mid from low + div(high - low, 2)" do
      code = """
      defmodule Search do
        def find(list, low, high) do
          mid = low + div(high - low, 2)
          Enum.at(list, mid)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      issue = hd(issues)
      assert issue.rule == :no_enum_at_midpoint_access
      assert issue.message =~ "List.to_tuple/1"
      assert issue.meta.line != nil
    end

    test "flags Enum.at with mid from div(low + high, 2)" do
      code = """
      defmodule Search do
        def find(list, low, high) do
          mid = div(low + high, 2)
          Enum.at(list, mid)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags Enum.at with mid from div(high - low, 2) + low" do
      code = """
      defmodule Search do
        def find(list, low, high) do
          mid = div(high - low, 2) + low
          Enum.at(list, mid)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags inline midpoint expression" do
      code = """
      defmodule Inline do
        def find(list, low, high) do
          Enum.at(list, div(low + high, 2))
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags piped Enum.at with midpoint variable" do
      code = """
      defmodule Piped do
        def find(list, low, high) do
          mid = low + div(high - low, 2)
          list |> Enum.at(mid)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags piped Enum.at with inline midpoint" do
      code = """
      defmodule Piped do
        def find(list, low, high) do
          list |> Enum.at(div(low + high, 2))
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags multiple list variables" do
      code = """
      defmodule Multi do
        def compare(keys, values, low, high) do
          mid = low + div(high - low, 2)
          k = Enum.at(keys, mid)
          v = Enum.at(values, mid)
          {k, v}
        end
      end
      """

      assert length(check(code)) == 2
    end

    test "flags Enum.at inside anonymous fn (reduce_while pattern)" do
      code = """
      defmodule Iterative do
        def search(list, target) do
          Enum.reduce_while(0..100, {0, length(list) - 1}, fn _, {low, high} ->
            mid = low + div(high - low, 2)
            mid_val = Enum.at(list, mid)

            cond do
              mid_val == target -> {:halt, {:ok, mid}}
              mid_val < target -> {:cont, {mid + 1, high}}
              true -> {:cont, {low, mid - 1}}
            end
          end)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags defp functions" do
      code = """
      defmodule Private do
        defp lookup(list, low, high) do
          mid = div(low + high, 2)
          Enum.at(list, mid)
        end
      end
      """

      assert length(check(code)) == 1
    end
  end

  describe "ignores recursive functions" do
    test "does not flag recursive function" do
      code = """
      defmodule Recursive do
        def search(list, target, low, high) when low <= high do
          mid = low + div(high - low, 2)
          mid_val = Enum.at(list, mid)

          cond do
            mid_val == target -> mid
            mid_val < target -> search(list, target, mid + 1, high)
            true -> search(list, target, low, mid - 1)
          end
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "ignores safe code" do
    test "passes code using elem/tuple" do
      code = """
      defmodule Fast do
        def find(tuple, low, high) do
          mid = div(low + high, 2)
          elem(tuple, mid)
        end
      end
      """

      assert check(code) == []
    end

    test "passes Enum.at with literal indices" do
      code = """
      defmodule Config do
        def first(list) do
          Enum.at(list, 0)
        end
      end
      """

      assert check(code) == []
    end

    test "passes Enum.at with simple dynamic index" do
      code = """
      defmodule Example do
        def get(list, i) do
          Enum.at(list, i)
        end
      end
      """

      assert check(code) == []
    end

    test "passes when mid is a parameter, not derived from midpoint math" do
      code = """
      defmodule Example do
        def foo(list, mid) do
          Enum.at(list, mid)
        end
      end
      """

      assert check(code) == []
    end

    test "passes when mid comes from non-midpoint expression" do
      code = """
      defmodule Other do
        def foo(list) do
          mid = String.length("hello")
          Enum.at(list, mid)
        end
      end
      """

      assert check(code) == []
    end
  end
end
