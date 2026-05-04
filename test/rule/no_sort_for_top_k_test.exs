defmodule Credence.Rule.NoSortForTopKTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoSortForTopK.check(ast, [])
  end

  defp fix(code) do
    Credence.Rule.NoSortForTopK.fix(code, [])
  end

  # ── check — positive cases ───────────────────────────────────────

  describe "check — positive cases" do
    test "flags sort |> take(1)" do
      code = """
      defmodule Bad do
        def f(list), do: Enum.sort(list) |> Enum.take(1)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_sort_for_top_k
      assert issue.message =~ "Enum.min"
    end

    test "flags sort |> hd()" do
      code = """
      defmodule Bad do
        def f(list), do: Enum.sort(list) |> hd()
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.min"
    end

    test "flags sort |> Enum.at(0)" do
      code = """
      defmodule Bad do
        def f(list), do: Enum.sort(list) |> Enum.at(0)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.min"
    end

    test "flags sort |> reverse |> take(1)" do
      code = """
      defmodule Bad do
        def f(list), do: Enum.sort(list) |> Enum.reverse() |> Enum.take(1)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.max"
    end

    test "flags sort |> reverse |> hd()" do
      code = """
      defmodule Bad do
        def f(list), do: Enum.sort(list) |> Enum.reverse() |> hd()
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.max"
    end

    test "flags sort |> reverse |> Enum.at(0)" do
      code = """
      defmodule Bad do
        def f(list), do: Enum.sort(list) |> Enum.reverse() |> Enum.at(0)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.max"
    end

    test "flags inside anonymous function" do
      code = """
      Enum.map(list, fn x -> Enum.sort(x) |> Enum.take(1) end)
      """

      assert length(check(code)) == 1
    end

    test "flags with longer pipeline before sort (multiline)" do
      code = """
      defmodule Bad do
        def f(list) do
          Enum.sort(list)
          |> Enum.take(1)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags nested pipeline in tuple" do
      code = """
      Enum.map(list, &{&1, Enum.sort(&1) |> Enum.take(1)})
      """

      assert length(check(code)) == 1
    end
  end

  # ── check — negative cases ───────────────────────────────────────

  describe "check — negative cases" do
    test "does not flag sort |> take(k>1)" do
      code = """
      defmodule Good do
        def f(list), do: Enum.sort(list) |> Enum.take(2)
      end
      """

      assert check(code) == []
    end

    test "does not flag sort |> at(1)" do
      code = """
      defmodule Good do
        def f(list), do: Enum.sort(list) |> Enum.at(1)
      end
      """

      assert check(code) == []
    end

    test "does not flag sort |> take(1) followed by more steps" do
      code = """
      Enum.sort(list) |> Enum.take(1) |> length()
      """

      assert check(code) == []
    end

    test "does not flag unrelated pipelines" do
      code = """
      defmodule Good do
        def f(list), do: list |> Enum.map(&(&1 * 2)) |> Enum.take(1)
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.min directly" do
      code = """
      defmodule Good do
        def f(list), do: Enum.min(list)
      end
      """

      assert check(code) == []
    end

    test "does not flag graphemes stored then counted" do
      code = """
      defmodule Good do
        def f(list) do
          sorted = Enum.sort(list)
          hd(sorted)
        end
      end
      """

      assert check(code) == []
    end
  end

  # ── fix ──────────────────────────────────────────────────────────

  describe "fix" do
    test "sort |> take(1) → Enum.min" do
      result = fix("Enum.sort(list) |> Enum.take(1)")
      assert result =~ "Enum.min(list)"
      refute result =~ "Enum.sort(list)"
      refute result =~ "Enum.take(1)"
    end

    test "sort |> hd() → Enum.min" do
      result = fix("Enum.sort(list) |> hd()")
      assert result =~ "Enum.min(list)"
    end

    test "sort |> Enum.at(0) → Enum.min" do
      result = fix("Enum.sort(list) |> Enum.at(0)")
      assert result =~ "Enum.min(list)"
    end

    test "sort |> reverse |> take(1) → Enum.max" do
      result = fix("Enum.sort(list) |> Enum.reverse() |> Enum.take(1)")
      assert result =~ "Enum.max(list)"
      refute result =~ "Enum.sort"
      refute result =~ "Enum.reverse"
    end

    test "sort |> reverse |> hd() → Enum.max" do
      result = fix("Enum.sort(list) |> Enum.reverse() |> hd()")
      assert result =~ "Enum.max(list)"
    end

    test "sort |> reverse |> Enum.at(0) → Enum.max" do
      result = fix("Enum.sort(list) |> Enum.reverse() |> Enum.at(0)")
      assert result =~ "Enum.max(list)"
    end

    test "sort |> reverse |> reverse |> take(1) → Enum.min (double reverse is no-op)" do
      result =
        fix("Enum.sort(list) |> Enum.reverse() |> Enum.reverse() |> Enum.take(1)")

      assert result =~ "Enum.min(list)"
    end

    test "fixes pattern inside function body" do
      source = """
      defmodule Example do
        def f(list), do: Enum.sort(list) |> Enum.take(1)
      end
      """

      result = fix(source)
      assert result =~ "Enum.min(list)"
      refute result =~ "Enum.sort(list)"
    end

    test "fixes pattern inside Enum.map" do
      source = "Enum.map(lists, fn l -> Enum.sort(l) |> Enum.take(1) end)"
      result = fix(source)
      assert result =~ "Enum.min(l)"
    end

    test "fixes multiple occurrences" do
      source = """
      defmodule Example do
        def f(a, b) do
          x = Enum.sort(a) |> Enum.take(1)
          y = Enum.sort(b) |> Enum.reverse() |> Enum.at(0)
          {x, y}
        end
      end
      """

      result = fix(source)
      assert result =~ "Enum.min(a)"
      assert result =~ "Enum.max(b)"
      refute result =~ "Enum.sort(a)"
      refute result =~ "Enum.sort(b)"
    end

    test "fixes sort |> take(1) in assignment" do
      source = "result = Enum.sort(list) |> Enum.take(1)"
      result = fix(source)
      assert result =~ "Enum.min(list)"
    end

    test "does not change non-fixable patterns" do
      code = "Enum.sort(list) |> Enum.take(2)"
      assert fix(code) == code
    end

    test "does not change sort |> take(1) followed by more steps" do
      code = "Enum.sort(list) |> Enum.take(1) |> length()"
      result = fix(code)
      assert result =~ "Enum.sort(list)"
      assert result =~ "Enum.take(1)"
    end

    test "does not change code without fixable patterns" do
      code = """
      defmodule Example do
        def f(list), do: Enum.min(list)
      end
      """

      assert fix(code) == code
    end
  end
end
