defmodule Credence.Pattern.NoKeywordGetIntegerKeyFixTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoKeywordGetIntegerKey.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoKeywordGetIntegerKey.fix(code, [])
  end

  # ── index -1 → List.last ──────────────────────────────────────

  describe "index -1 → List.last" do
    test "direct call" do
      assert fix("Keyword.get(acc, -1)") == "List.last(acc)"
    end

    test "in assignment" do
      assert fix("prev = Keyword.get(acc, -1)") == "prev = List.last(acc)"
    end

    test "piped" do
      assert fix("acc |> Keyword.get(-1)") == "acc |> List.last()"
    end
  end

  # ── index 0 → List.first ──────────────────────────────────────

  describe "index 0 → List.first" do
    test "direct call" do
      assert fix("Keyword.get(list, 0)") == "List.first(list)"
    end

    test "piped" do
      assert fix("list |> Keyword.get(0)") == "list |> List.first()"
    end
  end

  # ── general integer → Enum.at ──────────────────────────────────

  describe "general integer → Enum.at" do
    test "positive index" do
      assert fix("Keyword.get(list, 3)") == "Enum.at(list, 3)"
    end

    test "negative index" do
      assert fix("Keyword.get(list, -2)") == "Enum.at(list, -2)"
    end

    test "piped positive" do
      assert fix("list |> Keyword.get(3)") == "list |> Enum.at(3)"
    end

    test "piped negative" do
      assert fix("list |> Keyword.get(-2)") == "list |> Enum.at(-2)"
    end
  end

  # ── realistic context ──────────────────────────────────────────

  describe "realistic context" do
    test "preserves surrounding code" do
      code = """
      defmodule Example do
        def last_value(acc) do
          prev = Keyword.get(acc, -1)
          prev * 2
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "prev = List.last(acc)"
      assert fixed =~ "prev * 2"
      refute fixed =~ "Keyword.get"
    end

    test "the actual pattern from the LLM log" do
      assert fix("prev_value = Keyword.get(acc, -1)") == "prev_value = List.last(acc)"
    end
  end

  # ── no-ops ─────────────────────────────────────────────────────

  describe "no-ops" do
    test "atom key unchanged" do
      code = "Keyword.get(opts, :name)"
      assert fix(code) == code
    end

    test "variable key unchanged" do
      code = "Keyword.get(opts, key)"
      assert fix(code) == code
    end

    test "Map.get with integer key unchanged" do
      code = "Map.get(map, -1)"
      assert fix(code) == code
    end

    test "no Keyword.get at all" do
      code = "List.last(acc)"
      assert fix(code) == code
    end
  end

  # ── round-trip ─────────────────────────────────────────────────

  describe "round-trip" do
    test "fixed code produces zero issues" do
      code = """
      defmodule Example do
        def first(l), do: Keyword.get(l, 0)
        def last(l), do: Keyword.get(l, -1)
        def third(l), do: Keyword.get(l, 2)
      end
      """

      assert check(fix(code)) == []
    end

    test "fixed code is valid Elixir" do
      code = """
      defmodule Example do
        def first(l), do: Keyword.get(l, 0)
        def last(l), do: Keyword.get(l, -1)
        def middle(l), do: Keyword.get(l, 3)
      end
      """

      assert {:ok, _} = Code.string_to_quoted(fix(code))
    end
  end
end
