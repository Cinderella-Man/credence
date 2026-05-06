defmodule Credence.Pattern.NoIdentityFunctionInEnumTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoIdentityFunctionInEnum.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoIdentityFunctionInEnum.fix(code, [])
  end

  describe "fixable?/0" do
    test "reports as fixable" do
      assert Credence.Pattern.NoIdentityFunctionInEnum.fixable?() == true
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # CHECK — positive cases
  # ═══════════════════════════════════════════════════════════════════

  describe "check/2 — detects identity fn in _by variants" do
    test "flags Enum.uniq_by with fn x -> x end" do
      code = """
      defmodule Example do
        def run(list), do: Enum.uniq_by(list, fn x -> x end)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_identity_function_in_enum
      assert issue.message =~ "Enum.uniq"
    end

    test "flags Enum.sort_by with fn item -> item end" do
      code = """
      defmodule Example do
        def run(list), do: Enum.sort_by(list, fn item -> item end)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.sort"
    end

    test "flags Enum.min_by with fn x -> x end" do
      code = """
      defmodule Example do
        def run(list), do: Enum.min_by(list, fn x -> x end)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.min"
    end

    test "flags Enum.max_by with fn x -> x end" do
      code = """
      defmodule Example do
        def run(list), do: Enum.max_by(list, fn x -> x end)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.max"
    end

    test "flags Enum.dedup_by with fn x -> x end" do
      code = """
      defmodule Example do
        def run(list), do: Enum.dedup_by(list, fn x -> x end)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.dedup"
    end

    test "flags piped form with identity fn" do
      code = """
      defmodule Example do
        def run(list), do: list |> Enum.uniq_by(fn x -> x end)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_identity_function_in_enum
    end

    test "flags & &1 capture" do
      code = """
      defmodule Example do
        def run(list), do: Enum.sort_by(list, & &1)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.sort"
    end

    test "flags piped & &1" do
      code = """
      defmodule Example do
        def run(list), do: list |> Enum.uniq_by(& &1)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_identity_function_in_enum
    end

    test "flags with long variable name" do
      code = """
      defmodule Example do
        def run(items), do: items |> Enum.uniq_by(fn grapheme -> grapheme end)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_identity_function_in_enum
    end

    test "flags inside a pipeline" do
      code = """
      defmodule Example do
        def run(str) do
          str |> String.graphemes() |> Enum.uniq_by(fn g -> g end)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_identity_function_in_enum
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # CHECK — negative cases
  # ═══════════════════════════════════════════════════════════════════

  describe "check/2 — negative cases" do
    test "does not flag Enum.uniq (already simplified)" do
      code = """
      defmodule Example do
        def run(list), do: Enum.uniq(list)
      end
      """

      assert check(code) == []
    end

    test "does not flag non-identity function" do
      code = """
      defmodule Example do
        def run(list), do: Enum.sort_by(list, fn x -> -x end)
      end
      """

      assert check(code) == []
    end

    test "does not flag uniq_by with a transformation" do
      code = """
      defmodule Example do
        def run(list), do: Enum.uniq_by(list, fn x -> String.downcase(x) end)
      end
      """

      assert check(code) == []
    end

    test "does not flag uniq_by with field access" do
      code = """
      defmodule Example do
        def run(list), do: Enum.uniq_by(list, & &1.name)
      end
      """

      assert check(code) == []
    end

    test "does not flag fn with different variables in arg and body" do
      code = """
      defmodule Example do
        def run(list), do: Enum.sort_by(list, fn x -> y end)
      end
      """

      assert check(code) == []
    end

    test "does not flag multi-clause fn" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.sort_by(list, fn
            nil -> 0
            x -> x
          end)
        end
      end
      """

      assert check(code) == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX — direct calls
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/2 — direct calls" do
    test "fixes Enum.uniq_by(list, fn x -> x end) → Enum.uniq(list)" do
      code = """
      defmodule Example do
        def run(list), do: Enum.uniq_by(list, fn x -> x end)
      end
      """

      fixed = fix(code)
      assert fixed =~ "Enum.uniq(list)"
      refute fixed =~ "uniq_by"
    end

    test "fixes Enum.sort_by(list, fn x -> x end) → Enum.sort(list)" do
      code = """
      defmodule Example do
        def run(list), do: Enum.sort_by(list, fn item -> item end)
      end
      """

      fixed = fix(code)
      assert fixed =~ "Enum.sort(list)"
      refute fixed =~ "sort_by"
    end

    test "fixes Enum.min_by(list, fn x -> x end) → Enum.min(list)" do
      code = """
      defmodule Example do
        def run(list), do: Enum.min_by(list, fn x -> x end)
      end
      """

      fixed = fix(code)
      assert fixed =~ "Enum.min(list)"
      refute fixed =~ "min_by"
    end

    test "fixes Enum.max_by(list, & &1) → Enum.max(list)" do
      code = """
      defmodule Example do
        def run(list), do: Enum.max_by(list, & &1)
      end
      """

      fixed = fix(code)
      assert fixed =~ "Enum.max(list)"
      refute fixed =~ "max_by"
    end

    test "fixes Enum.dedup_by(list, fn x -> x end) → Enum.dedup(list)" do
      code = """
      defmodule Example do
        def run(list), do: Enum.dedup_by(list, fn x -> x end)
      end
      """

      fixed = fix(code)
      assert fixed =~ "Enum.dedup(list)"
      refute fixed =~ "dedup_by"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX — piped calls
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/2 — piped calls" do
    test "fixes |> Enum.uniq_by(fn x -> x end) → |> Enum.uniq()" do
      code = """
      defmodule Example do
        def run(list), do: list |> Enum.uniq_by(fn x -> x end)
      end
      """

      fixed = fix(code)
      assert fixed =~ "Enum.uniq()"
      refute fixed =~ "uniq_by"
    end

    test "fixes in a longer pipeline" do
      code = """
      defmodule Example do
        def run(str) do
          str |> String.graphemes() |> Enum.uniq_by(fn g -> g end)
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "String.graphemes()"
      assert fixed =~ "Enum.uniq()"
      refute fixed =~ "uniq_by"
    end

    test "fixes piped & &1" do
      code = """
      defmodule Example do
        def run(list), do: list |> Enum.sort_by(& &1)
      end
      """

      fixed = fix(code)
      assert fixed =~ "Enum.sort()"
      refute fixed =~ "sort_by"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX — edge cases
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/2 — edge cases" do
    test "does not touch non-identity callbacks" do
      code = """
      defmodule Example do
        def run(list), do: Enum.sort_by(list, fn x -> -x end)
      end
      """

      assert fix(code) == code
    end

    test "returns source unchanged when nothing to fix" do
      code = """
      defmodule Example do
        def run(list), do: Enum.uniq(list)
      end
      """

      assert fix(code) == code
    end

    test "preserves surrounding code" do
      code = """
      defmodule Example do
        def foo(x), do: x + 1
        def bar(list), do: list |> Enum.uniq_by(fn x -> x end)
        def baz(y), do: y * 2
      end
      """

      fixed = fix(code)
      assert fixed =~ "def foo(x), do: x + 1"
      assert fixed =~ "Enum.uniq()"
      assert fixed =~ "def baz(y), do: y * 2"
    end
  end
end
