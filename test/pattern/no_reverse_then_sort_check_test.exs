defmodule Credence.Pattern.NoReverseThenSortCheckTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoReverseThenSort

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoReverseThenSort.check(ast, [])
  end

  # ── FLAGGED: reverse then sort ──────────────────────────────────────────

  describe "flags reverse then sort" do
    test "pipeline: reverse then sort" do
      code = "defmodule M do\n  def f(x), do: x |> Enum.reverse() |> Enum.sort()\nend"
      assert [%Issue{rule: :no_reverse_then_sort}] = check(code)
    end

    test "pipeline: multi-step before reverse" do
      code =
        "defmodule M do\n  def f(x), do: x |> Enum.filter(&(&1 > 0)) |> Enum.reverse() |> Enum.sort()\nend"

      assert [%Issue{rule: :no_reverse_then_sort}] = check(code)
    end

    test "direct call piped to sort" do
      code = "defmodule M do\n  def f(x), do: Enum.reverse(x) |> Enum.sort()\nend"
      assert [%Issue{rule: :no_reverse_then_sort}] = check(code)
    end

    test "nested call" do
      code = "defmodule M do\n  def f(x), do: Enum.sort(Enum.reverse(x))\nend"
      assert [%Issue{rule: :no_reverse_then_sort}] = check(code)
    end
  end

  # ── NOT FLAGGED: unrelated patterns ─────────────────────────────────────

  describe "does NOT flag unrelated patterns" do
    test "sort without preceding reverse" do
      code = "defmodule M do\n  def f(x), do: x |> Enum.sort()\nend"
      assert check(code) == []
    end

    test "reverse without following sort" do
      code = "defmodule M do\n  def f(x), do: Enum.reverse(x)\nend"
      assert check(code) == []
    end

    test "reverse then something else" do
      code = "defmodule M do\n  def f(x), do: x |> Enum.reverse() |> Enum.map(&(&1 + 1))\nend"
      assert check(code) == []
    end

    test "sort then reverse (handled by no_sort_then_reverse)" do
      code = "defmodule M do\n  def f(x), do: x |> Enum.sort() |> Enum.reverse()\nend"
      assert check(code) == []
    end
  end
end
