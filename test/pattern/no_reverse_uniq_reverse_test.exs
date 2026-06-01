defmodule Credence.Pattern.NoReverseUniqReverseTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoReverseUniqReverse

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoReverseUniqReverse.check(ast, [])
  end

  # ── FLAGGED ────────────────────────────────────────────────────────────────

  describe "flags reverse |> uniq |> reverse" do
    test "pipeline with Enum.uniq/1" do
      code =
        "defmodule M do\n  def f(x), do: x |> Enum.reverse() |> Enum.uniq() |> Enum.reverse()\nend"

      assert [%Issue{rule: :no_reverse_uniq_reverse}] = check(code)
    end

    test "pipeline with Enum.uniq_by/2" do
      code =
        "defmodule M do\n  def f(x), do: x |> Enum.reverse() |> Enum.uniq_by(&elem(&1, 0)) |> Enum.reverse()\nend"

      assert [%Issue{rule: :no_reverse_uniq_reverse}] = check(code)
    end

    test "nested call form" do
      code = "defmodule M do\n  def f(x), do: Enum.reverse(Enum.uniq(Enum.reverse(x)))\nend"
      assert [%Issue{rule: :no_reverse_uniq_reverse}] = check(code)
    end

    test "nested with uniq_by" do
      code =
        "defmodule M do\n  def f(x), do: Enum.reverse(Enum.uniq_by(Enum.reverse(x), &elem(&1, 0)))\nend"

      assert [%Issue{rule: :no_reverse_uniq_reverse}] = check(code)
    end

    test "longer pipeline still flagged" do
      code =
        "defmodule M do\n  def f(x), do: x |> Enum.filter(&(&1 > 0)) |> Enum.reverse() |> Enum.uniq() |> Enum.reverse()\nend"

      assert [%Issue{rule: :no_reverse_uniq_reverse}] = check(code)
    end
  end

  # ── NOT FLAGGED ────────────────────────────────────────────────────────────

  describe "does NOT flag unrelated patterns" do
    test "reverse |> uniq without trailing reverse" do
      code = "defmodule M do\n  def f(x), do: x |> Enum.reverse() |> Enum.uniq()\nend"
      assert check(code) == []
    end

    test "uniq |> reverse (uniq first)" do
      code = "defmodule M do\n  def f(x), do: x |> Enum.uniq() |> Enum.reverse()\nend"
      assert check(code) == []
    end

    test "Enum.uniq/1 alone" do
      code = "defmodule M do\n  def f(x), do: Enum.uniq(x)\nend"
      assert check(code) == []
    end

    test "reverse |> sort |> reverse (different middle func)" do
      code =
        "defmodule M do\n  def f(x), do: x |> Enum.reverse() |> Enum.sort() |> Enum.reverse()\nend"

      assert check(code) == []
    end

    test "reverse |> map |> reverse" do
      code =
        "defmodule M do\n  def f(x), do: x |> Enum.reverse() |> Enum.map(&(&1 + 1)) |> Enum.reverse()\nend"

      assert check(code) == []
    end

    test "nested Enum.reverse(Enum.uniq(x)) without inner reverse" do
      code = "defmodule M do\n  def f(x), do: Enum.reverse(Enum.uniq(x))\nend"
      assert check(code) == []
    end

    test "single reverse" do
      code = "defmodule M do\n  def f(x), do: Enum.reverse(x)\nend"
      assert check(code) == []
    end
  end
end
