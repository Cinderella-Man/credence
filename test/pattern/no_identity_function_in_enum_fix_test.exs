defmodule Credence.Pattern.NoIdentityFunctionInEnumFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoIdentityFunctionInEnum

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoIdentityFunctionInEnum, code, [])
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  describe "fix/2 — direct calls" do
    test "fixes Enum.uniq_by(list, fn x -> x end) → Enum.uniq(list)" do
      input = """
      defmodule Example do
        def run(list), do: Enum.uniq_by(list, fn x -> x end)
      end
      """

      expected = """
      defmodule Example do
        def run(list), do: Enum.uniq(list)
      end
      """

      assert fix(input) == expected
    end

    test "fixes Enum.sort_by(list, fn x -> x end) → Enum.sort(list)" do
      input = """
      defmodule Example do
        def run(list), do: Enum.sort_by(list, fn item -> item end)
      end
      """

      expected = """
      defmodule Example do
        def run(list), do: Enum.sort(list)
      end
      """

      assert fix(input) == expected
    end

    test "fixes Enum.min_by(list, fn x -> x end) → Enum.min(list)" do
      input = """
      defmodule Example do
        def run(list), do: Enum.min_by(list, fn x -> x end)
      end
      """

      expected = """
      defmodule Example do
        def run(list), do: Enum.min(list)
      end
      """

      assert fix(input) == expected
    end

    test "fixes Enum.max_by(list, & &1) → Enum.max(list)" do
      input = """
      defmodule Example do
        def run(list), do: Enum.max_by(list, & &1)
      end
      """

      expected = """
      defmodule Example do
        def run(list), do: Enum.max(list)
      end
      """

      assert fix(input) == expected
    end

    test "fixes Enum.dedup_by(list, fn x -> x end) → Enum.dedup(list)" do
      input = """
      defmodule Example do
        def run(list), do: Enum.dedup_by(list, fn x -> x end)
      end
      """

      expected = """
      defmodule Example do
        def run(list), do: Enum.dedup(list)
      end
      """

      assert fix(input) == expected
    end
  end

  describe "fix/2 — piped calls" do
    test "fixes |> Enum.uniq_by(fn x -> x end) → |> Enum.uniq()" do
      input = """
      defmodule Example do
        def run(list), do: list |> Enum.uniq_by(fn x -> x end)
      end
      """

      expected = """
      defmodule Example do
        def run(list), do: list |> Enum.uniq()
      end
      """

      assert fix(input) == expected
    end

    test "fixes in a longer pipeline" do
      input = """
      defmodule Example do
        def run(str) do
          str |> String.graphemes() |> Enum.uniq_by(fn g -> g end)
        end
      end
      """

      expected = """
      defmodule Example do
        def run(str) do
          str |> String.graphemes() |> Enum.uniq()
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes piped & &1" do
      input = """
      defmodule Example do
        def run(list), do: list |> Enum.sort_by(& &1)
      end
      """

      expected = """
      defmodule Example do
        def run(list), do: list |> Enum.sort()
      end
      """

      assert fix(input) == expected
    end
  end

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
      input = """
      defmodule Example do
        def foo(x), do: x + 1
        def bar(list), do: list |> Enum.uniq_by(fn x -> x end)
        def baz(y), do: y * 2
      end
      """

      expected = """
      defmodule Example do
        def foo(x), do: x + 1
        def bar(list), do: list |> Enum.uniq()
        def baz(y), do: y * 2
      end
      """

      assert fix(input) == expected
    end
  end
end
