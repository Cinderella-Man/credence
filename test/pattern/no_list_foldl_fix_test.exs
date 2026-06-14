defmodule Credence.Pattern.NoListFoldlFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoListFoldl

  describe "fix" do
    test "replaces direct List.foldl with Enum.reduce" do
      input = "List.foldl(list, 0, fn x, acc -> acc + x end)"

      expected = "Enum.reduce(list, 0, fn x, acc -> acc + x end)"

      confirm_fix(fix(NoListFoldl, input), expected)
    end

    test "replaces piped List.foldl with Enum.reduce" do
      input = "list |> List.foldl(0, fn x, acc -> acc + x end)"

      expected = "list |> Enum.reduce(0, fn x, acc -> acc + x end)"

      confirm_fix(fix(NoListFoldl, input), expected)
    end

    test "does not modify Enum.reduce" do
      code = "Enum.reduce(list, 0, fn x, acc -> acc + x end)"

      confirm_fix(fix(NoListFoldl, code), code)
    end

    test "does not modify List.foldr (out of scope)" do
      code = "List.foldr(list, [], fn x, acc -> [x | acc] end)"

      confirm_fix(fix(NoListFoldl, code), code)
    end

    test "preserves surrounding code" do
      input = """
      defmodule M do
        def run(list) do
          sum = List.foldl(list, 0, fn x, acc -> acc + x end)
          sum * 2
        end
      end
      """

      expected = """
      defmodule M do
        def run(list) do
          sum = Enum.reduce(list, 0, fn x, acc -> acc + x end)
          sum * 2
        end
      end
      """

      confirm_fix(fix(NoListFoldl, input), expected)
    end

    test "fixed foldl produces no issues" do
      code = "List.foldl(list, 0, fn x, acc -> acc + x end)"

      assert check(NoListFoldl, fix(NoListFoldl, code)) == []
    end
  end
end
