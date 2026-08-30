defmodule Credence.Pattern.NoSortForTopKFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoSortForTopK

  describe "fix (Enum.at(0) terminal → Enum.min/max with empty_fallback)" do
    test "sort |> Enum.at(0) → Enum.min(_, fn -> nil end)" do
      input = "Enum.sort(list) |> Enum.at(0)"

      expected = "Enum.min(list, fn -> nil end)"

      confirm_fix(fix(NoSortForTopK, input), expected)
    end

    test "sort |> reverse |> Enum.at(0) → Enum.max(_, &>/2, fn -> nil end)" do
      input = "Enum.sort(list) |> Enum.reverse() |> Enum.at(0)"

      expected = "Enum.max(list, &>/2, fn -> nil end)"

      confirm_fix(fix(NoSortForTopK, input), expected)
    end

    test "sort |> reverse |> reverse |> Enum.at(0) → Enum.min (double reverse is no-op)" do
      input = "Enum.sort(list) |> Enum.reverse() |> Enum.reverse() |> Enum.at(0)"

      expected = "Enum.min(list, fn -> nil end)"

      confirm_fix(fix(NoSortForTopK, input), expected)
    end

    test "fixes pattern inside function body" do
      input = """
      defmodule Example do
        def f(list), do: Enum.sort(list) |> Enum.at(0)
      end
      """

      expected = """
      defmodule Example do
        def f(list), do: Enum.min(list, fn -> nil end)
      end
      """

      confirm_fix(fix(NoSortForTopK, input), expected)
    end

    test "fixes pattern inside Enum.map" do
      input = "Enum.map(lists, fn l -> Enum.sort(l) |> Enum.at(0) end)"

      expected = "Enum.map(lists, fn l -> Enum.min(l, fn -> nil end) end)"

      confirm_fix(fix(NoSortForTopK, input), expected)
    end

    test "fixes multiple occurrences" do
      input = """
      defmodule Example do
        def f(a, b) do
          x = Enum.sort(a) |> Enum.at(0)
          y = Enum.sort(b) |> Enum.reverse() |> Enum.at(0)
          {x, y}
        end
      end
      """

      expected = """
      defmodule Example do
        def f(a, b) do
          x = Enum.min(a, fn -> nil end)
          y = Enum.max(b, &>/2, fn -> nil end)
          {x, y}
        end
      end
      """

      confirm_fix(fix(NoSortForTopK, input), expected)
    end

    test "fixes sort |> Enum.at(0) in assignment" do
      input = "result = Enum.sort(list) |> Enum.at(0)"

      expected = "result = Enum.min(list, fn -> nil end)"

      confirm_fix(fix(NoSortForTopK, input), expected)
    end
  end

  describe "no-ops (deliberately not fixed)" do
    test "does not change sort |> take(1) (list vs scalar)" do
      code = "Enum.sort(list) |> Enum.take(1)"

      confirm_fix(fix(NoSortForTopK, code), code)
    end

    test "does not change sort |> hd() (exception type mismatch on [])" do
      code = "Enum.sort(list) |> hd()"

      confirm_fix(fix(NoSortForTopK, code), code)
    end

    test "does not change sort |> reverse |> take(1)" do
      code = "Enum.sort(list) |> Enum.reverse() |> Enum.take(1)"

      confirm_fix(fix(NoSortForTopK, code), code)
    end

    test "does not change non-fixable take(k>1)" do
      code = "Enum.sort(list) |> Enum.take(2)"

      confirm_fix(fix(NoSortForTopK, code), code)
    end

    test "does not change sort |> Enum.at(0) followed by more steps" do
      code = "Enum.sort(list) |> Enum.at(0) |> to_string()"

      confirm_fix(fix(NoSortForTopK, code), code)
    end

    test "does not change code without fixable patterns" do
      code = """
      defmodule Example do
        def f(list), do: Enum.min(list)
      end
      """

      confirm_fix(fix(NoSortForTopK, code), code)
    end
  end
end
