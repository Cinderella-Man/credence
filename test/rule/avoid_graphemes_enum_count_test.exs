defmodule Credence.Pattern.AvoidGraphemesEnumCountTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.AvoidGraphemesEnumCount.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.AvoidGraphemesEnumCount.fix(code, [])
  end

  describe "AvoidGraphemesEnumCount" do
    # --- POSITIVE CASES (should flag) ---

    test "flags simple pipeline" do
      code = """
      defmodule Example do
        def run(str), do: str |> String.graphemes() |> Enum.count()
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :avoid_graphemes_enum_count
    end

    test "flags Enum.count(String.graphemes(str))" do
      code = """
      defmodule Example do
        def run(str), do: Enum.count(String.graphemes(str))
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "flags direct call with predicate: Enum.count(String.graphemes(str), pred)" do
      code = """
      defmodule Example do
        def run(str), do: Enum.count(String.graphemes(str), &(&1 == "a"))
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :avoid_graphemes_enum_count
    end

    test "Enum.count with predicate on graphemes" do
      code = """
      defmodule VowelCounter do
        @vowels ~w(a e i o u)

        def count_vowels(text) do
          text
          |> String.downcase()
          |> String.graphemes()
          |> Enum.count(&(&1 in @vowels))
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags with longer pipeline before graphemes" do
      code = """
      defmodule Example do
        def run(str), do:
          str
          |> String.trim()
          |> String.upcase()
          |> String.graphemes()
          |> Enum.count()
      end
      """

      assert length(check(code)) == 1
    end

    test "flags inside Enum.map" do
      code = """
      Enum.map(list, fn x ->
        String.graphemes(x) |> Enum.count()
      end)
      """

      assert length(check(code)) == 1
    end

    test "flags nested pipeline in tuple" do
      code = """
      Enum.map(list, &{&1, &1 |> String.graphemes() |> Enum.count()})
      """

      assert length(check(code)) == 1
    end

    test "flags multiple violations in the same module" do
      code = """
      defmodule Example do
        def count(str), do: String.graphemes(str) |> Enum.count()
        def vowels(str), do: String.graphemes(str) |> Enum.count(&(&1 in ~w(a e i o u)))
      end
      """

      assert length(check(code)) == 2
    end

    test "flags two-step pipe: String.graphemes(x) |> Enum.count()" do
      code = """
      defmodule Example do
        def run(str), do: String.graphemes(str) |> Enum.count()
      end
      """

      assert length(check(code)) == 1
    end

    # --- NEGATIVE CASES (should NOT flag) ---

    test "does not flag String.length/1" do
      code = """
      defmodule Example do
        def run(str), do: String.length(str)
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.count/1 on non-graphemes" do
      code = """
      defmodule Example do
        def run(list), do: Enum.count(list)
      end
      """

      assert check(code) == []
    end

    test "does not flag when graphemes result is used" do
      code = """
      defmodule Example do
        def run(str), do: String.graphemes(str) |> Enum.reverse()
      end
      """

      assert check(code) == []
    end

    test "does not flag when there is an intermediate step before Enum.count" do
      code = """
      defmodule Example do
        def run(str), do:
          str
          |> String.graphemes()
          |> Enum.map(& &1)
          |> Enum.count()
      end
      """

      assert check(code) == []
    end

    test "does not flag when Enum.count is applied after transformations" do
      code = """
      defmodule Example do
        def run(str), do:
          str
          |> String.graphemes()
          |> Enum.filter(&(&1 != " "))
          |> Enum.count()
      end
      """

      assert check(code) == []
    end

    test "does not flag graphemes stored then counted later" do
      code = """
      defmodule Example do
        def run(str) do
          g = String.graphemes(str)
          Enum.count(g)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag String.codepoints |> Enum.count()" do
      code = """
      defmodule Example do
        def run(str), do: String.codepoints(str) |> Enum.count()
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.count/2 on non-graphemes with predicate" do
      code = """
      defmodule Example do
        def run(list), do: Enum.count(list, &(&1 > 0))
      end
      """

      assert check(code) == []
    end
  end

  describe "fix/2 — no predicate (→ String.length)" do
    test "fixes direct call: Enum.count(String.graphemes(x))" do
      code = """
      defmodule Example do
        def run(str), do: Enum.count(String.graphemes(str))
      end
      """

      result = fix(code)

      assert result =~ "String.length"
      refute result =~ "Enum.count"
      refute result =~ "graphemes"
    end

    test "fixes two-step pipe: String.graphemes(x) |> Enum.count()" do
      code = """
      defmodule Example do
        def run(str), do: String.graphemes(str) |> Enum.count()
      end
      """

      result = fix(code)

      assert result =~ "String.length(str)"
      refute result =~ "Enum.count"
    end

    test "fixes three-step pipe: x |> String.graphemes() |> Enum.count()" do
      code = """
      defmodule Example do
        def run(str), do: str |> String.graphemes() |> Enum.count()
      end
      """

      result = fix(code)

      assert result =~ "String.length"
      refute result =~ "graphemes"
      refute result =~ "Enum.count"
    end

    test "fixes longer pipeline, preserving upstream steps" do
      code = """
      defmodule Example do
        def run(str) do
          str
          |> String.trim()
          |> String.downcase()
          |> String.graphemes()
          |> Enum.count()
        end
      end
      """

      result = fix(code)

      assert result =~ "String.trim"
      assert result =~ "String.downcase"
      assert result =~ "String.length"
      refute result =~ "graphemes"
    end
  end

  describe "fix/2 — with predicate (→ Stream.unfold)" do
    test "fixes pipe form: String.graphemes(x) |> Enum.count(pred)" do
      code = """
      defmodule Example do
        def run(str), do: String.graphemes(str) |> Enum.count(&(&1 == "a"))
      end
      """

      result = fix(code)

      assert result =~ "Stream.unfold"
      assert result =~ "String.next_grapheme"
      assert result =~ "Enum.count"
      refute result =~ "String.graphemes"
    end

    test "fixes direct call: Enum.count(String.graphemes(x), pred)" do
      code = """
      defmodule Example do
        def run(str), do: Enum.count(String.graphemes(str), &(&1 == "a"))
      end
      """

      result = fix(code)

      assert result =~ "Stream.unfold"
      assert result =~ "String.next_grapheme"
      assert result =~ "Enum.count"
      refute result =~ "String.graphemes"
    end

    test "fixes longer pipeline with predicate" do
      code = """
      defmodule VowelCounter do
        @vowels ~w(a e i o u)

        def count_vowels(text) do
          text
          |> String.downcase()
          |> String.graphemes()
          |> Enum.count(&(&1 in @vowels))
        end
      end
      """

      result = fix(code)

      assert result =~ "String.downcase"
      assert result =~ "Stream.unfold"
      assert result =~ "Enum.count"
      refute result =~ "String.graphemes"
    end

    test "preserves the predicate expression exactly" do
      code = """
      defmodule Example do
        def run(str), do: Enum.count(String.graphemes(str), fn g -> g == "x" end)
      end
      """

      result = fix(code)

      assert result =~ ~r/fn g -> g == "x" end/
      assert result =~ "Stream.unfold"
    end
  end

  describe "fix/2 — mixed and edge cases" do
    test "fixes both violation types in the same module" do
      code = """
      defmodule Example do
        def count(str), do: String.graphemes(str) |> Enum.count()
        def vowels(str), do: String.graphemes(str) |> Enum.count(&(&1 in ~w(a e i o u)))
      end
      """

      result = fix(code)

      assert result =~ "String.length"
      assert result =~ "Stream.unfold"
      refute result =~ "String.graphemes"
    end

    test "does not alter code without violations" do
      code = """
      defmodule Example do
        def run(str), do: String.length(str)
        def filter(list), do: Enum.count(list, &(&1 > 0))
      end
      """

      result = fix(code)

      assert result =~ "String.length(str)"
      assert result =~ "Enum.count(list"
    end

    test "round-trip: fixed code produces zero issues" do
      code = """
      defmodule Example do
        def a(s), do: String.graphemes(s) |> Enum.count()
        def b(s), do: Enum.count(String.graphemes(s))
        def c(s), do: String.graphemes(s) |> Enum.count(&(&1 == "x"))
        def d(s), do: Enum.count(String.graphemes(s), &(&1 == "x"))
      end
      """

      fixed = fix(code)
      {:ok, ast} = Code.string_to_quoted(fixed)
      assert [] == Credence.Pattern.AvoidGraphemesEnumCount.check(ast, [])
    end

    test "fixed code is valid Elixir" do
      code = """
      defmodule Example do
        def a(s), do: String.graphemes(s) |> Enum.count()
        def b(s), do: String.graphemes(s) |> Enum.count(&(&1 == "x"))
      end
      """

      fixed = fix(code)
      assert {:ok, _} = Code.string_to_quoted(fixed)
    end
  end
end
