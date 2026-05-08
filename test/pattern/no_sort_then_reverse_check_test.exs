defmodule Credence.Pattern.NoSortThenReverseCheckTest do
  use ExUnit.Case

  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoSortThenReverse.check(ast, [])
  end

  # ── FLAGGED: atom direction ─────────────────────────────────────────────

  describe "flags sort then reverse with known direction" do
    test "pipeline default asc" do
      code = "defmodule M do\n  def f(x), do: x |> Enum.sort() |> Enum.reverse()\nend"
      assert [%Issue{rule: :no_sort_then_reverse}] = check(code)
    end

    test "pipeline explicit :asc" do
      code = "defmodule M do\n  def f(x), do: x |> Enum.sort(:asc) |> Enum.reverse()\nend"
      assert [%Issue{rule: :no_sort_then_reverse}] = check(code)
    end

    test "pipeline :desc" do
      code = "defmodule M do\n  def f(x), do: x |> Enum.sort(:desc) |> Enum.reverse()\nend"
      assert [%Issue{rule: :no_sort_then_reverse}] = check(code)
    end

    test "nested call" do
      code = "defmodule M do\n  def f(x), do: Enum.reverse(Enum.sort(x))\nend"
      assert [%Issue{rule: :no_sort_then_reverse}] = check(code)
    end

    test "longer pipeline" do
      code = "defmodule M do\n  def f(x), do: x |> Enum.filter(&(&1 > 0)) |> Enum.sort() |> Enum.reverse()\nend"
      assert [%Issue{rule: :no_sort_then_reverse}] = check(code)
    end

    test "direct call piped to reverse" do
      code = "defmodule M do\n  def f(x), do: Enum.sort(x) |> Enum.reverse()\nend"
      assert [%Issue{rule: :no_sort_then_reverse}] = check(code)
    end
  end

  # ── FLAGGED: function captures ──────────────────────────────────────────

  describe "flags sort with captures then reverse" do
    test "&>=/2 pipeline" do
      code = "defmodule M do\n  def f(x), do: Enum.sort(x, &>=/2) |> Enum.reverse()\nend"
      assert [%Issue{rule: :no_sort_then_reverse}] = check(code)
    end

    test "&<=/2 pipeline" do
      code = "defmodule M do\n  def f(x), do: Enum.sort(x, &<=/2) |> Enum.reverse()\nend"
      assert [%Issue{rule: :no_sort_then_reverse}] = check(code)
    end

    test "&>=/2 nested" do
      code = "defmodule M do\n  def f(x), do: Enum.reverse(Enum.sort(x, &>=/2))\nend"
      assert [%Issue{rule: :no_sort_then_reverse}] = check(code)
    end
  end

  # ── FLAGGED: anonymous comparators ──────────────────────────────────────

  describe "flags sort with anonymous comparator then reverse" do
    test "fn a, b -> a > b end pipeline" do
      code = "defmodule M do\n  def f(x), do: Enum.sort(x, fn a, b -> a > b end) |> Enum.reverse()\nend"
      assert [%Issue{rule: :no_sort_then_reverse}] = check(code)
    end

    test "fn a, b -> a < b end nested" do
      code = "defmodule M do\n  def f(x), do: Enum.reverse(Enum.sort(x, fn a, b -> a < b end))\nend"
      assert [%Issue{rule: :no_sort_then_reverse}] = check(code)
    end

    test "flipped fn a, b -> b < a end pipeline" do
      code = "defmodule M do\n  def f(x), do: Enum.sort(x, fn a, b -> b < a end) |> Enum.reverse()\nend"
      assert [%Issue{rule: :no_sort_then_reverse}] = check(code)
    end
  end

  # ── NOT FLAGGED: unresolvable direction ─────────────────────────────────

  describe "does NOT flag unresolvable direction" do
    test "variable direction" do
      code = "defmodule M do\n  def f(x, dir), do: Enum.sort(x, dir) |> Enum.reverse()\nend"
      assert check(code) == []
    end

    test "opaque comparator" do
      code = "defmodule M do\n  def f(x), do: Enum.sort(x, &MyModule.compare/2) |> Enum.reverse()\nend"
      assert check(code) == []
    end
  end

  # ── NOT FLAGGED: unrelated patterns ─────────────────────────────────────

  describe "does NOT flag unrelated patterns" do
    test "sort with :desc and no reverse" do
      code = "defmodule M do\n  def f(x), do: Enum.sort(x, :desc) |> Enum.take(3)\nend"
      assert check(code) == []
    end

    test "reverse without preceding sort" do
      code = "defmodule M do\n  def f(x), do: Enum.reverse(x)\nend"
      assert check(code) == []
    end
  end
end
