defmodule Credence.Pattern.NoReverseThenFindTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoReverseThenFind

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoReverseThenFind.check(ast, [])
  end

  # ── FLAGGED ────────────────────────────────────────────────────────────────

  describe "flags reverse |> find" do
    test "pipeline with Enum.find/2" do
      code =
        "defmodule M do\n  def f(x), do: x |> Enum.reverse() |> Enum.find(&is_even/1)\nend"

      assert [%Issue{rule: :no_reverse_then_find}] = check(code)
    end

    test "pipeline with Enum.find/3" do
      code =
        "defmodule M do\n  def f(x), do: x |> Enum.reverse() |> Enum.find(nil, &is_even/1)\nend"

      assert [%Issue{rule: :no_reverse_then_find}] = check(code)
    end

    test "pipeline with Enum.find_value/2" do
      code =
        "defmodule M do\n  def f(x), do: x |> Enum.reverse() |> Enum.find_value(fn v -> v * 2 end)\nend"

      assert [%Issue{rule: :no_reverse_then_find}] = check(code)
    end

    test "pipeline with Enum.find_value/3" do
      code =
        "defmodule M do\n  def f(x), do: x |> Enum.reverse() |> Enum.find_value(0, fn\n    {0, _} -> false\n    {_, i} -> i\n  end)\nend"

      assert [%Issue{rule: :no_reverse_then_find}] = check(code)
    end

    test "nested call: Enum.find(Enum.reverse(x))" do
      code = "defmodule M do\n  def f(x), do: Enum.find(Enum.reverse(x), &is_even/1)\nend"
      assert [%Issue{rule: :no_reverse_then_find}] = check(code)
    end

    test "nested call: Enum.find_value(Enum.reverse(x))" do
      code =
        "defmodule M do\n  def f(x), do: Enum.find_value(Enum.reverse(x), 0, fn v -> v end)\nend"

      assert [%Issue{rule: :no_reverse_then_find}] = check(code)
    end

    test "longer pipeline still flagged" do
      code =
        "defmodule M do\n  def f(x), do: x |> Enum.with_index() |> Enum.reverse() |> Enum.find(fn {0, _} -> false; {_, _} -> true end)\nend"

      assert [%Issue{rule: :no_reverse_then_find}] = check(code)
    end
  end

  # ── NOT FLAGGED ────────────────────────────────────────────────────────────

  describe "does NOT flag unrelated patterns" do
    test "reverse |> map" do
      code = "defmodule M do\n  def f(x), do: x |> Enum.reverse() |> Enum.map(&(&1 + 1))\nend"
      assert check(code) == []
    end

    test "reverse |> sort (different rule)" do
      code = "defmodule M do\n  def f(x), do: x |> Enum.reverse() |> Enum.sort()\nend"
      assert check(code) == []
    end

    test "find without reverse" do
      code = "defmodule M do\n  def f(x), do: Enum.find(x, &is_even/1)\nend"
      assert check(code) == []
    end

    test "find_value without reverse" do
      code = "defmodule M do\n  def f(x), do: Enum.find_value(x, 0, fn v -> v end)\nend"
      assert check(code) == []
    end

    test "reverse |> filter (not find)" do
      code =
        "defmodule M do\n  def f(x), do: x |> Enum.reverse() |> Enum.filter(&is_even/1)\nend"

      assert check(code) == []
    end

    test "single reverse" do
      code = "defmodule M do\n  def f(x), do: Enum.reverse(x)\nend"
      assert check(code) == []
    end

    test "reverse |> each" do
      code =
        "defmodule M do\n  def f(x), do: x |> Enum.reverse() |> Enum.each(&IO.puts/1)\nend"

      assert check(code) == []
    end
  end
end
